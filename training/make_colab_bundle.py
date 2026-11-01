"""Package only the reviewed training sources, datasets, and v11 seed adapter."""

import argparse
import hashlib
import json
import tempfile
import zipfile
from pathlib import Path


ROOT = Path(__file__).parent
SEED_ADAPTER = ROOT / "output" / "pcbuild-qwen3.5-2b-qlora-v11"
SOURCE_SCRIPTS = {
    "convert_coco_pc.py",
    "evaluate_adapter.py",
    "make_colab_bundle.py",
    "prepare_colab_dataset.py",
    "prepare_dataset.py",
    "prepare_safety_v10_dataset.py",
    "prepare_safety_v11_dataset.py",
    "prepare_targeted_dataset.py",
    "serve_adapter.py",
    "train_lora.py",
    "train_pc_vision.py",
    "train_qlora.py",
}


def digest(path: Path) -> str:
    value = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            value.update(chunk)
    return value.hexdigest()


def collect_files() -> list[Path]:
    files = {ROOT / name for name in SOURCE_SCRIPTS if (ROOT / name).is_file()}
    files.update(ROOT.glob("*.md"))
    files.update(ROOT.glob("*.txt"))
    files.update((ROOT / "data").glob("*.jsonl"))
    if not (SEED_ADAPTER / "adapter_model.safetensors").is_file():
        raise FileNotFoundError(f"The v11 seed adapter is missing: {SEED_ADAPTER}")
    files.update(path for path in SEED_ADAPTER.iterdir() if path.is_file())
    return sorted(files, key=lambda path: path.relative_to(ROOT.parent).as_posix())


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", type=Path, default=None)
    args = parser.parse_args()

    output = args.output or (Path(tempfile.gettempdir()) / "pcbuild-colab-bundle.zip")
    output = output.resolve()
    output.parent.mkdir(parents=True, exist_ok=True)
    members = collect_files()
    manifest = {
        "format": 1,
        "purpose": "PCBUILD offline AI training bundle for Google Colab",
        "included_seed_adapter": "training/output/pcbuild-qwen3.5-2b-qlora-v11",
        "files": {
            path.relative_to(ROOT.parent).as_posix(): digest(path)
            for path in members
        },
    }

    temporary = output.with_suffix(output.suffix + ".tmp")
    with zipfile.ZipFile(temporary, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=1) as archive:
        for path in members:
            archive.write(path, path.relative_to(ROOT.parent).as_posix())
        archive.writestr("COLAB_BUNDLE_MANIFEST.json", json.dumps(manifest, indent=2))
    temporary.replace(output)
    size_mib = output.stat().st_size / (1024 * 1024)
    print(json.dumps({"bundle": str(output), "files": len(members), "size_mib": round(size_mib, 1)}, indent=2))


if __name__ == "__main__":
    main()
