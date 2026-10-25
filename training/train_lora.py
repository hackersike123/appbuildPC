"""LoRA fine-tuning for Qwen3.5-0.8B on a 6 GB GPU, using PC-only synthetic data."""

import argparse
import json
import random
from pathlib import Path

import torch
from peft import LoraConfig, get_peft_model
from torch.nn.utils.rnn import pad_sequence
from transformers import (
    AutoModelForMultimodalLM,
    AutoProcessor,
    Trainer,
    TrainingArguments,
)


ROOT = Path(__file__).parent
DATA = ROOT / "data" / "pc_sft.jsonl"
MODEL_ID = "Qwen/Qwen3.5-0.8B"
OUTPUT = ROOT / "output" / "pcbuild-qwen3.5-0.8b-lora"
MAX_LENGTH = 768


def read_data(path: Path):
    rows = []
    with path.open(encoding="utf-8") as f:
        for line in f:
            if line.strip():
                rows.append(json.loads(line)["messages"])
    if len(rows) < 20:
        raise ValueError(f"Expected at least 20 training examples, found {len(rows)}")
    return rows


def encode_rows(processor, conversations):
    tokenizer = processor.tokenizer
    encoded = []
    for messages in conversations:
        prefix = processor.apply_chat_template(
            messages[:-1], tokenize=True, add_generation_prompt=True, return_dict=True, return_tensors="pt"
        )
        full = processor.apply_chat_template(
            messages, tokenize=True, add_generation_prompt=False, return_dict=True, return_tensors="pt"
        )
        ids = full["input_ids"].squeeze(0)[:MAX_LENGTH]
        mask = full.get("attention_mask", torch.ones_like(full["input_ids"])).squeeze(0)[:MAX_LENGTH]
        labels = ids.clone()
        prompt_length = min(prefix["input_ids"].shape[-1], labels.shape[-1])
        labels[:prompt_length] = -100
        if not (labels != -100).any():
            continue
        row = {"input_ids": ids, "attention_mask": mask, "labels": labels}
        for key, value in full.items():
            if key not in row and isinstance(value, torch.Tensor) and value.ndim >= 2 and value.shape[-1] == full["input_ids"].shape[-1]:
                row[key] = value.squeeze(0)[:MAX_LENGTH]
        encoded.append(row)
    if len(encoded) < 20:
        raise ValueError(f"Only {len(encoded)} examples have assistant tokens after encoding")
    return encoded


class PcCollator:
    def __init__(self, pad_id: int):
        self.pad_id = pad_id

    def __call__(self, features):
        ids = pad_sequence([x["input_ids"] for x in features], batch_first=True, padding_value=self.pad_id)
        masks = pad_sequence([x["attention_mask"] for x in features], batch_first=True, padding_value=0)
        labels = pad_sequence([x["labels"] for x in features], batch_first=True, padding_value=-100)
        batch = {"input_ids": ids, "attention_mask": masks, "labels": labels}
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
    parser.add_argument("--model", default=MODEL_ID)
    parser.add_argument("--output", type=Path, default=OUTPUT)
    args = parser.parse_args()

    if not torch.cuda.is_available():
        raise RuntimeError("CUDA GPU is required; refusing to start a slow CPU run")
    if not torch.cuda.is_bf16_supported():
        raise RuntimeError("This training recipe expects GPU bfloat16 support")

    random.seed(42)
    torch.manual_seed(42)
    conversations = read_data(DATA)
    processor = AutoProcessor.from_pretrained(args.model)
    processor.tokenizer.padding_side = "right"
    if processor.tokenizer.pad_token_id is None:
        processor.tokenizer.pad_token = processor.tokenizer.eos_token
    encoded = encode_rows(processor, conversations)
    random.shuffle(encoded)
    eval_count = max(4, round(len(encoded) * 0.1))
    eval_set, train_set = encoded[:eval_count], encoded[eval_count:]

    model = AutoModelForMultimodalLM.from_pretrained(
        args.model,
        dtype=torch.bfloat16,
        low_cpu_mem_usage=True,
        attn_implementation="sdpa",
    )
    for name, parameter in model.named_parameters():
        if any(part in name.lower() for part in ("visual", "vision", "merger", "projector")):
            parameter.requires_grad_(False)
    model.config.use_cache = False
    if hasattr(model, "gradient_checkpointing_enable"):
        model.gradient_checkpointing_enable(gradient_checkpointing_kwargs={"use_reentrant": False})
    if hasattr(model, "enable_input_require_grads"):
        model.enable_input_require_grads()

    targets = choose_language_lora_targets(model)
    model = get_peft_model(
        model,
        LoraConfig(
            task_type="CAUSAL_LM",
            target_modules=targets,
            r=8,
            lora_alpha=16,
            lora_dropout=0.05,
            bias="none",
        ),
    )
    model.print_trainable_parameters()

    training_args = TrainingArguments(
        output_dir=str(args.output),
        num_train_epochs=args.epochs,
        per_device_train_batch_size=1,
        per_device_eval_batch_size=1,
        gradient_accumulation_steps=4,
        learning_rate=5e-5,
        warmup_steps=2,
        weight_decay=0.01,
        logging_steps=1,
        eval_strategy="epoch",
        save_strategy="epoch",
        save_total_limit=2,
        load_best_model_at_end=True,
        bf16=True,
        gradient_checkpointing=True,
        gradient_checkpointing_kwargs={"use_reentrant": False},
        optim="adamw_torch",
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
    metrics.update({"model_id": args.model, "examples": len(encoded), "train_examples": len(train_set), "eval_examples": len(eval_set), "lora_targets": targets})
    (args.output / "training_metrics.json").write_text(json.dumps(metrics, indent=2), encoding="utf-8")
    print(json.dumps(metrics, indent=2))


if __name__ == "__main__":
    main()
