"""QLoRA fine-tuning of the stronger Qwen3.5-2B multimodal model."""

import argparse
import hashlib
import json
import os
import random
import shutil
from datetime import datetime, timezone
from pathlib import Path

import torch
from peft import LoraConfig, PeftModel, get_peft_model, prepare_model_for_kbit_training
from torch.nn.utils.rnn import pad_sequence
from transformers import (
    AutoModelForMultimodalLM,
    AutoProcessor,
    BitsAndBytesConfig,
    EarlyStoppingCallback,
    Trainer,
    TrainerCallback,
    TrainingArguments,
)
from transformers.trainer_utils import get_last_checkpoint


ROOT = Path(__file__).parent
DATA = ROOT / "data" / "pc_sft.jsonl"
MODEL_ID = "Qwen/Qwen3.5-2B"
OUTPUT = ROOT / "output" / "pcbuild-qwen3.5-2b-qlora-v3"
MAX_LENGTH = 768


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def write_json_atomic(path: Path, value: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_name(f".{path.name}.{os.getpid()}.tmp")
    temporary.write_text(json.dumps(value, ensure_ascii=False, indent=2), encoding="utf-8")
    temporary.replace(path)


class ColabPersistenceCallback(TrainerCallback):
    """Mirror checkpoints and progress to Drive without an external tracker."""

    def __init__(self, output_dir: Path, backup_dir: Path, keep_checkpoints: int = 2):
        self.output_dir = output_dir
        self.backup_dir = backup_dir
        self.keep_checkpoints = keep_checkpoints
        self.backup_dir.mkdir(parents=True, exist_ok=True)

    @staticmethod
    def _replace_directory(source: Path, destination: Path) -> None:
        staging = destination.with_name(f".{destination.name}.uploading-{os.getpid()}")
        if staging.exists():
            shutil.rmtree(staging)
        shutil.copytree(source, staging)

        previous = destination.with_name(f".{destination.name}.previous-{os.getpid()}")
        if previous.exists():
            shutil.rmtree(previous)
        if destination.exists():
            destination.replace(previous)
        try:
            staging.replace(destination)
        except Exception:
            if previous.exists() and not destination.exists():
                previous.replace(destination)
            raise
        if previous.exists():
            shutil.rmtree(previous)

    def on_log(self, args, state, control, logs=None, **kwargs):
        if not state.is_world_process_zero or not logs:
            return control
        entry = {
            "timestamp_utc": datetime.now(timezone.utc).isoformat(),
            "step": state.global_step,
            "epoch": state.epoch,
            **{key: value for key, value in logs.items() if isinstance(value, (str, int, float, bool))},
        }
        line = json.dumps(entry, ensure_ascii=False)
        progress = self.backup_dir / "progress.jsonl"
        with progress.open("a", encoding="utf-8", newline="\n") as stream:
            stream.write(line + "\n")
            stream.flush()
            os.fsync(stream.fileno())
        write_json_atomic(self.backup_dir / "heartbeat.json", entry)
        return control

    def on_save(self, args, state, control, **kwargs):
        if not state.is_world_process_zero:
            return control
        checkpoint = self.output_dir / f"checkpoint-{state.global_step}"
        if not checkpoint.is_dir():
            raise FileNotFoundError(f"Trainer checkpoint is missing: {checkpoint}")
        destination = self.backup_dir / checkpoint.name
        self._replace_directory(checkpoint, destination)
        write_json_atomic(
            self.backup_dir / "latest_checkpoint.json",
            {
                "checkpoint": checkpoint.name,
                "global_step": state.global_step,
                "timestamp_utc": datetime.now(timezone.utc).isoformat(),
            },
        )

        checkpoints = sorted(
            self.backup_dir.glob("checkpoint-*"),
            key=lambda path: int(path.name.rsplit("-", 1)[-1]),
        )
        for old_checkpoint in checkpoints[:-self.keep_checkpoints]:
            shutil.rmtree(old_checkpoint)
        return control

    def sync_final_artifacts(self, metrics: dict) -> None:
        staging = self.backup_dir / f".final.uploading-{os.getpid()}"
        if staging.exists():
            shutil.rmtree(staging)
        staging.mkdir(parents=True)
        for artifact in self.output_dir.iterdir():
            if artifact.is_file():
                shutil.copy2(artifact, staging / artifact.name)
        write_json_atomic(staging / "training_metrics.json", metrics)
        write_json_atomic(
            staging / "artifact_manifest.json",
            {
                "timestamp_utc": datetime.now(timezone.utc).isoformat(),
                "files": {
                    artifact.name: sha256_file(artifact)
                    for artifact in staging.iterdir()
                    if artifact.is_file()
                },
            },
        )
        final = self.backup_dir / "final"
        previous = self.backup_dir / f".final.previous-{os.getpid()}"
        if previous.exists():
            shutil.rmtree(previous)
        if final.exists():
            final.replace(previous)
        try:
            staging.replace(final)
        except Exception:
            if previous.exists() and not final.exists():
                previous.replace(final)
            raise
        if previous.exists():
            shutil.rmtree(previous)


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
            return_dict=True, return_tensors="pt", enable_thinking=False
        )
        full = processor.apply_chat_template(
            messages, tokenize=True, add_generation_prompt=False,
            return_dict=True, return_tensors="pt", enable_thinking=False
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
    parser.add_argument("--resume-from-checkpoint", default=None, help="Checkpoint path or 'auto' under --output")
    parser.add_argument("--checkpoint-backup-dir", type=Path, default=None, help="Persistent Drive directory for checkpoints/logs")
    parser.add_argument("--save-steps", type=int, default=8)
    parser.add_argument("--eval-steps", type=int, default=8)
    parser.add_argument("--logging-steps", type=int, default=1)
    parser.add_argument("--report-to", choices=("none", "tensorboard"), default="none")
    parser.add_argument("--early-stopping-patience", type=int, default=0, help="Stop after this many evals without validation loss improvement; 0 disables it")
    parser.add_argument("--micro-batch-size", type=int, default=1, help="Per-device batch size; raise to improve GPU throughput when memory allows")
    parser.add_argument("--effective-batch-size", type=int, default=4, help="Train examples per optimizer update, excluding distributed workers")
    args = parser.parse_args()

    if not torch.cuda.is_available():
        raise RuntimeError("A CUDA GPU is required")
    if args.save_steps < 1 or args.eval_steps < 1 or args.logging_steps < 1:
        raise ValueError("save/eval/logging steps must all be positive")
    if args.save_steps != args.eval_steps:
        raise ValueError("--save-steps and --eval-steps must match when selecting the best checkpoint")
    if args.epochs <= 0:
        raise ValueError("--epochs must be positive")
    if args.early_stopping_patience < 0:
        raise ValueError("--early-stopping-patience cannot be negative")
    if args.micro_batch_size < 1 or args.effective_batch_size < 1:
        raise ValueError("--micro-batch-size and --effective-batch-size must be positive")
    if args.effective_batch_size % args.micro_batch_size:
        raise ValueError("--effective-batch-size must be divisible by --micro-batch-size")
    gradient_accumulation_steps = args.effective_batch_size // args.micro_batch_size
    random.seed(42)
    torch.manual_seed(42)
    torch.cuda.manual_seed_all(42)

    conversations = read_data(args.data)
    processor = AutoProcessor.from_pretrained(args.model)
    processor.tokenizer.padding_side = "right"
    if processor.tokenizer.pad_token_id is None:
        processor.tokenizer.pad_token = processor.tokenizer.eos_token
    encoded = encode_rows(processor, conversations)
    random.shuffle(encoded)
    eval_count = max(6, round(len(encoded) * 0.12))
    eval_set, train_set = encoded[:eval_count], encoded[eval_count:]

    capability_major, _ = torch.cuda.get_device_capability(0)
    use_bf16 = torch.cuda.is_bf16_supported() and capability_major >= 8
    compute_dtype = torch.bfloat16 if use_bf16 else torch.float16
    gpu_gib = torch.cuda.get_device_properties(0).total_memory / (1024 ** 3)
    gpu_memory_limit = f"{max(5, int(gpu_gib * 0.90))}GiB"
    quantization = BitsAndBytesConfig(
        load_in_4bit=True,
        bnb_4bit_quant_type="nf4",
        bnb_4bit_use_double_quant=True,
        bnb_4bit_compute_dtype=compute_dtype,
    )
    model = AutoModelForMultimodalLM.from_pretrained(
        args.model,
        quantization_config=quantization,
        device_map="auto",
        max_memory={0: gpu_memory_limit, "cpu": "10GiB"},
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
    print(f"Micro-batch size: {args.micro_batch_size}; effective batch size: {args.effective_batch_size}")

    training_args = TrainingArguments(
        output_dir=str(args.output),
        num_train_epochs=args.epochs,
        per_device_train_batch_size=args.micro_batch_size,
        per_device_eval_batch_size=args.micro_batch_size,
        gradient_accumulation_steps=gradient_accumulation_steps,
        learning_rate=args.learning_rate,
        warmup_steps=3,
        weight_decay=0.01,
        logging_steps=args.logging_steps,
        eval_strategy="steps",
        eval_steps=args.eval_steps,
        save_strategy="steps",
        save_steps=args.save_steps,
        save_total_limit=2,
        load_best_model_at_end=True,
        metric_for_best_model="eval_loss",
        greater_is_better=False,
        bf16=use_bf16,
        fp16=not use_bf16,
        gradient_checkpointing=True,
        gradient_checkpointing_kwargs={"use_reentrant": False},
        optim="paged_adamw_8bit",
        dataloader_num_workers=0,
        remove_unused_columns=False,
        report_to=["tensorboard"] if args.report_to == "tensorboard" else "none",
        seed=42,
    )
    backup_callback = None
    callbacks = []
    if args.early_stopping_patience:
        callbacks.append(EarlyStoppingCallback(
            early_stopping_patience=args.early_stopping_patience,
            early_stopping_threshold=0.0,
        ))
    if args.checkpoint_backup_dir:
        backup_callback = ColabPersistenceCallback(args.output, args.checkpoint_backup_dir)
        callbacks.append(backup_callback)
    trainer = Trainer(
        model=model,
        args=training_args,
        train_dataset=train_set,
        eval_dataset=eval_set,
        data_collator=PcCollator(processor.tokenizer.pad_token_id),
        callbacks=callbacks,
    )

    resume_from_checkpoint = args.resume_from_checkpoint
    if resume_from_checkpoint == "auto":
        resume_from_checkpoint = get_last_checkpoint(str(args.output))
    if resume_from_checkpoint and not Path(resume_from_checkpoint).is_dir():
        raise FileNotFoundError(f"Resume checkpoint not found: {resume_from_checkpoint}")

    result = trainer.train(resume_from_checkpoint=resume_from_checkpoint)
    trainer.save_model(str(args.output))
    processor.save_pretrained(args.output)
    metrics = {**result.metrics, **trainer.evaluate()}
    metrics.update({
        "model_id": args.model,
        "initialized_from_adapter": str(args.init_adapter) if args.init_adapter else None,
        "resumed_from_checkpoint": str(resume_from_checkpoint) if resume_from_checkpoint else None,
        "quantization": "4-bit NF4 double quantization",
        "compute_dtype": "bfloat16" if use_bf16 else "float16",
        "examples": len(encoded),
        "train_examples": len(train_set),
        "eval_examples": len(eval_set),
        "micro_batch_size": args.micro_batch_size,
        "effective_batch_size": args.effective_batch_size,
        "gradient_accumulation_steps": gradient_accumulation_steps,
        "lora_targets": targets,
        "data_sha256": sha256_file(args.data),
    })
    (args.output / "training_metrics.json").write_text(json.dumps(metrics, indent=2), encoding="utf-8")
    if backup_callback:
        backup_callback.sync_final_artifacts(metrics)
    print(json.dumps(metrics, indent=2))


if __name__ == "__main__":
    main()
