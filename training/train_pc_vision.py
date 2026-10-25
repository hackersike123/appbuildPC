"""Fine-tune a small local PC-component detector from an annotated YOLO dataset."""

import argparse
import json
import re
import shutil
from collections import Counter
from pathlib import Path

import yaml


ROOT = Path(__file__).parent
DEFAULT_OUTPUT = ROOT / "output" / "pcbuild-pcparts-yolo26n"

CLASS_ALIASES = {
    "CPU": {"cpu", "processor", "central processing unit"},
    "MAINBOARD": {"mainboard", "motherboard", "mboard"},
    "GPU": {"gpu", "graphics card", "video card", "vga"},
    "RAM": {"ram", "memory", "ram stick", "memory module"},
    "SSD": {"ssd", "solid state drive"},
    "STORAGE": {"hdd", "hard disk", "hard disk drive", "disk drive", "storage"},
    "PSU": {"psu", "power supply", "power supply unit"},
    "CASE": {"case", "pc case", "computer case", "chassis"},
    "COOLER": {"cooler", "cpu cooler", "cpu_cooler", "heatsink", "heat sink"},
}


def normalize_name(name: str) -> str:
    return re.sub(r"[^a-z0-9]+", " ", str(name).lower()).strip()


def load_dataset_yaml(path: Path) -> tuple[dict, list[str]]:
    config = yaml.safe_load(path.read_text(encoding="utf-8")) or {}
    names = config.get("names")
    if isinstance(names, dict):
        names = [names[key] for key in sorted(names, key=lambda value: int(value))]
    if not isinstance(names, list) or not names:
        raise ValueError("YOLO data.yaml must define names as a list or indexed mapping")
    aliases = {normalize_name(alias): target for target, values in CLASS_ALIASES.items() for alias in values}
    mapped = {name: aliases.get(normalize_name(name)) for name in names}
    recognized = {value for value in mapped.values() if value}
    if len(recognized) < 2:
        raise ValueError("Dataset must label at least two PC component categories")
    return config, names


def split_paths(config: dict, data_file: Path, split: str) -> tuple[list[Path], list[Path]]:
    value = config.get(split)
    if not value:
        raise ValueError(f"data.yaml must contain a separate '{split}' split for evaluation")
    base = Path(config.get("path") or data_file.parent)
    if not base.is_absolute():
        base = (data_file.parent / base).resolve()
    entries = value if isinstance(value, list) else [value]
    image_paths = []
    label_paths = []
    for entry in entries:
        source = Path(entry)
        if not source.is_absolute():
            source = (base / source).resolve()
        if not source.exists():
            raise FileNotFoundError(f"Dataset {split} path does not exist: {source}")
        images = sorted(source.rglob("*.jpg")) + sorted(source.rglob("*.jpeg")) + sorted(source.rglob("*.png"))
        if not images:
            raise ValueError(f"No images found under {source}")
        for image in images:
            parts = list(image.parts)
            try:
                image_index = max(i for i, part in enumerate(parts) if part.lower() == "images")
                parts[image_index] = "labels"
                label = Path(*parts).with_suffix(".txt")
            except ValueError as error:
                raise ValueError(f"YOLO image path must contain an 'images' directory: {image}") from error
            if not label.is_file():
                raise FileNotFoundError(f"Missing YOLO annotation for {image}: {label}")
            image_paths.append(image)
            label_paths.append(label)
    return image_paths, label_paths


def validate_annotations(labels: list[Path], class_names: list[str], split: str) -> Counter:
    counts = Counter()
    for label_file in labels:
        for line_number, row in enumerate(label_file.read_text(encoding="utf-8").splitlines(), start=1):
            fields = row.split()
            if not fields:
                continue
            class_id = int(fields[0])
            if class_id < 0 or class_id >= len(class_names):
                raise ValueError(f"Invalid class ID at {label_file}:{line_number}")
            if len(fields) != 5:
                raise ValueError(f"Expected YOLO box row with 5 fields at {label_file}:{line_number}")
            coordinates = [float(value) for value in fields[1:]]
            if any(value < 0 or value > 1 for value in coordinates):
                raise ValueError(f"YOLO normalized coordinates must be between 0 and 1 at {label_file}:{line_number}")
            counts[class_names[class_id]] += 1
    if split == "train" and sum(counts.values()) == 0:
        raise ValueError("The training split has no annotated objects")
    return counts


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--data", required=True, type=Path, help="YOLO dataset data.yaml with train/val/test splits")
    parser.add_argument("--dataset-source", required=True, help="Dataset title or source URL for attribution")
    parser.add_argument("--dataset-license", required=True, help="License label to record in model metadata")
    parser.add_argument("--model", default="yolo26n.pt")
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT)
    parser.add_argument("--epochs", type=int, default=80)
    parser.add_argument("--imgsz", type=int, default=640)
    parser.add_argument("--batch", type=int, default=8)
    parser.add_argument("--device", default="0")
    parser.add_argument("--workers", type=int, default=0)
    args = parser.parse_args()

    data_file = args.data.resolve()
    if not data_file.is_file():
        raise FileNotFoundError(f"Dataset config not found: {data_file}")
    config, class_names = load_dataset_yaml(data_file)
    split_counts = {}
    for split in ("train", "val", "test"):
        _, label_paths = split_paths(config, data_file, split)
        split_counts[split] = validate_annotations(label_paths, class_names, split)

    alias_map = {normalize_name(alias): target for target, values in CLASS_ALIASES.items() for alias in values}
    category_counts = Counter()
    for source_name, count in split_counts["train"].items():
        category = alias_map.get(normalize_name(source_name))
        if category:
            category_counts[category] += count
    trained_categories = sorted(category_counts)
    print(f"Classes in dataset: {class_names}")
    print(f"PC component categories detected: {trained_categories}")
    print(f"Training annotations: {sum(split_counts['train'].values())}")
    print(f"Validation annotations: {sum(split_counts['val'].values())}")
    print(f"Held-out test annotations: {sum(split_counts['test'].values())}")
    if len(trained_categories) < 4:
        raise ValueError("At least four PC component categories with training labels are required; add properly labeled images before training")
    rare = [name for name, count in category_counts.items() if count < 20]
    if rare:
        print(f"Warning: very few training boxes for original classes {rare}; expect weak generalization.")

    from ultralytics import YOLO

    model = YOLO(args.model)
    results = model.train(
        data=str(data_file),
        epochs=args.epochs,
        imgsz=args.imgsz,
        batch=args.batch,
        device=args.device,
        workers=args.workers,
        patience=15,
        cache=False,
        project=str(args.output),
        name="train",
        exist_ok=True,
        plots=True,
        verbose=True,
    )
    best = Path(model.trainer.best)
    stable_weights = args.output / "weights" / "best.pt"
    stable_weights.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(best, stable_weights)

    best_model = YOLO(str(stable_weights))
    metrics = best_model.val(
        data=str(data_file),
        split="test",
        imgsz=args.imgsz,
        batch=args.batch,
        device=args.device,
        plots=True,
        project=str(args.output),
        name="held-out-test",
        exist_ok=True,
    )
    report = {
        "dataset_source": args.dataset_source,
        "dataset_license": args.dataset_license,
        "dataset_config": str(data_file),
        "base_model": args.model,
        "trained_categories": trained_categories,
        "train_annotations": dict(split_counts["train"]),
        "validation_annotations": dict(split_counts["val"]),
        "test_annotations": dict(split_counts["test"]),
        "test_map50": float(metrics.box.map50),
        "test_map50_95": float(metrics.box.map),
        "best_weights": str(stable_weights.resolve()),
    }
    (args.output / "vision_metrics.json").write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
    print(json.dumps(report, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
