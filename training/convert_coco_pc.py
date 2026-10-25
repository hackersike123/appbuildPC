"""Convert separate COCO train/val/test annotations into a local YOLO dataset."""

import argparse
import json
from pathlib import Path

import yaml
from PIL import Image


def read_coco(path: Path) -> dict:
    document = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(document.get("images"), list) or not isinstance(document.get("categories"), list):
        raise ValueError(f"Not a COCO instances annotation file: {path}")
    return document


def find_image(image_root: Path, file_name: str) -> Path:
    relative = Path(file_name)
    if relative.is_absolute() or ".." in relative.parts:
        raise ValueError(f"Unsafe COCO file_name: {file_name}")
    source = (image_root / relative).resolve()
    if not source.is_file() or image_root.resolve() not in source.parents:
        raise FileNotFoundError(f"COCO image not found under {image_root}: {file_name}")
    return source


def convert_split(document: dict, image_root: Path, output_root: Path, split: str, class_ids: dict[int, int]) -> int:
    images = {int(item["id"]): item for item in document["images"]}
    labels_by_image = {image_id: [] for image_id in images}
    for annotation in document.get("annotations", []):
        image_id = int(annotation["image_id"])
        category_id = int(annotation["category_id"])
        if image_id not in images or category_id not in class_ids or annotation.get("iscrowd", 0):
            continue
        image = images[image_id]
        width, height = float(image["width"]), float(image["height"])
        x, y, box_width, box_height = map(float, annotation.get("bbox", [0, 0, 0, 0]))
        left, top = max(0.0, x), max(0.0, y)
        right, bottom = min(width, x + box_width), min(height, y + box_height)
        if width <= 0 or height <= 0 or right <= left or bottom <= top:
            continue
        center_x, center_y = (left + right) / 2 / width, (top + bottom) / 2 / height
        normalized_width, normalized_height = (right - left) / width, (bottom - top) / height
        labels_by_image[image_id].append(
            f"{class_ids[category_id]} {center_x:.6f} {center_y:.6f} {normalized_width:.6f} {normalized_height:.6f}"
        )

    image_output = output_root / "images" / split
    label_output = output_root / "labels" / split
    image_output.mkdir(parents=True, exist_ok=True)
    label_output.mkdir(parents=True, exist_ok=True)
    count = 0
    for image_id, metadata in images.items():
        source = find_image(image_root, str(metadata["file_name"]))
        target = image_output / f"{image_id}_{source.stem}.jpg"
        with Image.open(source) as opened:
            opened.convert("RGB").save(target, format="JPEG", quality=95)
        (label_output / f"{target.stem}.txt").write_text(
            "\n".join(labels_by_image[image_id]) + ("\n" if labels_by_image[image_id] else ""),
            encoding="utf-8",
        )
        count += len(labels_by_image[image_id])
    return count


def main() -> None:
    parser = argparse.ArgumentParser()
    for split in ("train", "val", "test"):
        parser.add_argument(f"--{split}-json", required=True, type=Path)
        parser.add_argument(f"--{split}-images", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()

    documents = {split: read_coco(getattr(args, f"{split}_json").resolve()) for split in ("train", "val", "test")}
    category_by_id = {int(item["id"]): str(item["name"]) for item in documents["train"]["categories"]}
    if not category_by_id:
        raise ValueError("The COCO training file has no categories")
    for split, document in documents.items():
        split_categories = {int(item["id"]): str(item["name"]) for item in document["categories"]}
        if split_categories != category_by_id:
            raise ValueError(f"COCO category IDs/names differ in the {split} split")

    ordered_ids = sorted(category_by_id)
    class_ids = {category_id: index for index, category_id in enumerate(ordered_ids)}
    class_names = [category_by_id[category_id] for category_id in ordered_ids]
    output = args.output.resolve()
    counts = {}
    for split in ("train", "val", "test"):
        counts[split] = convert_split(
            documents[split], getattr(args, f"{split}_images").resolve(), output, split, class_ids
        )
    data_config = {
        "path": output.as_posix(),
        "train": "images/train",
        "val": "images/val",
        "test": "images/test",
        "names": class_names,
    }
    (output / "data.yaml").write_text(yaml.safe_dump(data_config, sort_keys=False, allow_unicode=True), encoding="utf-8")
    print(json.dumps({"data_yaml": str(output / "data.yaml"), "categories": class_names, "boxes": counts}, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
