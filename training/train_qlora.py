"""QLoRA fine-tuning of the stronger Qwen3.5-2B multimodal model."""

import argparse
import json
import random
from pathlib import Path

import torch
from peft import LoraConfig, PeftModel, get_peft_model, prepare_model_for_kbit_training
from torch.nn.utils.rnn import pad_sequence
from transformers import (
    AutoModelForMultimodalLM,
    AutoProcessor,
    BitsAndBytesConfig,
    Trainer,
    TrainingArguments,
)


ROOT = Path(__file__).parent
DATA = ROOT / "data" / "pc_sft.jsonl"
MODEL_ID = "Qwen/Qwen3.5-2B"
OUTPUT = ROOT / "output" / "pcbuild-qwen3.5-2b-qlora-v3"
MAX_LENGTH = 768


def read_data(path: Path):
    rows = []
    with path.open(encoding="utf-8") as f:
        for line in f:
            if line.strip():
                rows.append(json.loads(line)["messages"])
    if len(rows) < 40:
        raise ValueError(f"Expected at least 40 training examples, found {len(rows)}")
    return rows


def encode_rows(processor, conversations):
    encoded = []
    for messages in conversations:
        prefix = processor.apply_chat_template(
            messages[:-1], tokenize=True, add_generation_prompt=True,
            return_dict=True, return_tensors="pt"
        )
        full = processor.apply_chat_template(
            messages, tokenize=True, add_generation_prompt=False,
            return_dict=True, return_tensors="pt"
        )
        ids = full["input_ids"].squeeze(0)[:MAX_LENGTH]
        mask = full.get("attention_mask", torch.ones_like(full["input_ids"])).squeeze(0)[:MAX_LENGTH]
        labels = ids.clone()
        labels[:min(prefix["input_ids"].shape[-1], labels.shape[-1])] = -100
        if not (labels != -100).any():
            continue
        row = {"input_ids": ids, "attention_mask": mask, "labels": labels}
        for key, value in full.items():
            if key not in row and isinstance(value, torch.Tensor) and value.ndim >= 2 and value.shape[-1] == full["input_ids"].shape[-1]:
                row[key] = value.squeeze(0)[:MAX_LENGTH]
        encoded.append(row)
    if len(encoded) < 40:
        raise ValueError(f"Only {len(encoded)} examples have assistant tokens after encoding")
    return encoded


class PcCollator:
    def __init__(self, pad_id: int):
        self.pad_id = pad_id

    def __call__(self, features):
        batch = {
            "input_ids": pad_sequence([x["input_ids"] for x in features], batch_first=True, padding_value=self.pad_id),
            "attention_mask": pad_sequence([x["attention_mask"] for x in features], batch_first=True, padding_value=0),
            "labels": pad_sequence([x["labels"] for x in features], batch_first=True, padding_value=-100),
        }
        for key in features[0]:
            if key not in batch:
                batch[key] = pad_sequence([x[key] for x in features], batch_first=True, padding_value=0)
        return batch


def choose_language_lora_targets(model):
    targets = set()
    for name, module in model.named_modules():
        lowered = name.lower()
        if any(part in lowered for part in ("visual", "vision", "merger", "projector")):
            continue
        if isinstance(module, torch.nn.Linear):
            targets.add(name.rsplit(".", 1)[-1])
    targets.discard("lm_head")
    if not targets:
        raise RuntimeError("Could not find language linear layers for LoRA")
    return sorted(targets)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--epochs", type=float, default=3)
    parser.add_argument("--learning-rate", type=float, default=2e-5)
    parser.add_argument("--model", default=MODEL_ID)
    parser.add_argument("--data", type=Path, default=DATA)
    parser.add_argument("--output", type=Path, default=OUTPUT)
    parser.add_argument("--init-adapter", type=Path, default=None)
    args = parser.parse_args()

    if not torch.cuda.is_available() or not torch.cuda.is_bf16_supported():
        raise RuntimeError("A CUDA GPU with bfloat16 support is required")
    random.seed(42)
    torch.manual_seed(42)

    conversations = read_data(args.data)
    processor = AutoProcessor.from_pretrained(args.model)
    processor.tokenizer.padding_side = "right"
    if processor.tokenizer.pad_token_id is None:
        processor.tokenizer.pad_token = processor.tokenizer.eos_token
    encoded = encode_rows(processor, conversations)
    random.shuffle(encoded)
    eval_count = max(6, round(len(encoded) * 0.12))
    eval_set, train_set = encoded[:eval_count], encoded[eval_count:]

    quantization = BitsAndBytesConfig(
        load_in_4bit=True,
        bnb_4bit_quant_type="nf4",
        bnb_4bit_use_double_quant=True,
        bnb_4bit_compute_dtype=torch.bfloat16,
    )
    model = AutoModelForMultimodalLM.from_pretrained(
        args.model,
        quantization_config=quantization,
        device_map="auto",
        max_memory={0: "5.3GiB", "cpu": "7GiB"},
        low_cpu_mem_usage=True,
        attn_implementation="sdpa",
    )
    for name, parameter in model.named_parameters():
        if any(part in name.lower() for part in ("visual", "vision", "merger", "projector")):
            parameter.requires_grad_(False)
    model = prepare_model_for_kbit_training(model, use_gradient_checkpointing=True)
    model.config.use_cache = False
    targets = choose_language_lora_targets(model)
    if args.init_adapter:
        model = PeftModel.from_pretrained(model, args.init_adapter, is_trainable=True)
    else:
        model = get_peft_model(
            model,
            LoraConfig(
                task_type="CAUSAL_LM",
                target_modules=targets,
                r=16,
                lora_alpha=32,
                lora_dropout=0.05,
                bias="none",
            ),
        )
    model.print_trainable_parameters()
    print(f"CUDA memory after model/LoRA load: {torch.cuda.memory_allocated() / 1024**3:.2f} GiB")

    training_args = TrainingArguments(
        output_dir=str(args.output),
        num_train_epochs=args.epochs,
        per_device_train_batch_size=1,
        per_device_eval_batch_size=1,
        gradient_accumulation_steps=4,
        learning_rate=args.learning_rate,
        warmup_steps=3,
        weight_decay=0.01,
        logging_steps=1,
        eval_strategy="epoch",
        save_strategy="epoch",
        save_total_limit=2,
        load_best_model_at_end=True,
        bf16=True,
        gradient_checkpointing=True,
        gradient_checkpointing_kwargs={"use_reentrant": False},
        optim="paged_adamw_8bit",
        dataloader_num_workers=0,
        remove_unused_columns=False,
        report_to="none",
        seed=42,
    )
    trainer = Trainer(
        model=model,
        args=training_args,
        train_dataset=train_set,
        eval_dataset=eval_set,
        data_collator=PcCollator(processor.tokenizer.pad_token_id),
    )
    result = trainer.train()
    trainer.save_model(str(args.output))
    processor.save_pretrained(args.output)
    metrics = {**result.metrics, **trainer.evaluate()}
    metrics.update({
        "model_id": args.model,
        "initialized_from_adapter": str(args.init_adapter) if args.init_adapter else None,
        "quantization": "4-bit NF4 double quantization",
        "examples": len(encoded),
        "train_examples": len(train_set),
        "eval_examples": len(eval_set),
        "lora_targets": targets,
    })
    (args.output / "training_metrics.json").write_text(json.dumps(metrics, indent=2), encoding="utf-8")
    print(json.dumps(metrics, indent=2))


if __name__ == "__main__":
    main()
