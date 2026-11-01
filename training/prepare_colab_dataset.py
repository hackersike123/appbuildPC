"""Combine the reviewed general and v12 correction examples for Colab QLoRA."""

import argparse
import json
import os
from pathlib import Path


ROOT = Path(__file__).parent


def read_rows(path: Path, source: str) -> list[dict]:
    rows = []
    with path.open(encoding="utf-8") as stream:
        for line_number, line in enumerate(stream, start=1):
            if not line.strip():
                continue
            row = json.loads(line)
            messages = row.get("messages")
            if not isinstance(messages, list) or len(messages) != 3:
                raise ValueError(f"Expected system/user/assistant messages at {path}:{line_number}")
            if [message.get("role") for message in messages] != ["system", "user", "assistant"]:
                raise ValueError(f"Unexpected message roles at {path}:{line_number}")
            if any(not isinstance(message.get("content"), str) or not message["content"].strip() for message in messages):
                raise ValueError(f"Empty or non-text message at {path}:{line_number}")
            rows.append({"messages": messages, "source": source})
    if not rows:
        raise ValueError(f"No examples found in {path}")
    return rows


def normalized_prompt(row: dict) -> str:
    return " ".join(row["messages"][1]["content"].split()).casefold()


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--general", type=Path, default=ROOT / "data" / "pc_sft.jsonl")
    parser.add_argument("--corrections", type=Path, default=ROOT / "data" / "pc_safety_v12.jsonl")
    parser.add_argument("--output", type=Path, default=ROOT / "data" / "pc_colab_sft.jsonl")
    args = parser.parse_args()

    general_rows = read_rows(args.general, "pc_sft")
    correction_rows = read_rows(args.corrections, "pc_safety_v12")
    general_systems = {row["messages"][0]["content"] for row in general_rows}
    correction_systems = {row["messages"][0]["content"] for row in correction_rows}
    if len(general_systems) != 1 or len(correction_systems) != 1:
        raise ValueError("Each source must use one consistent system prompt")

    # Apply the stricter corrective prompt to general examples too, so the model
    # does not learn conflicting safety rules from mixed system messages.
    strict_system = correction_rows[0]["messages"][0]["content"]
    for row in general_rows:
        row["messages"][0]["content"] = strict_system
    rows = general_rows + correction_rows
    prompts = [normalized_prompt(row) for row in rows]
    if len(set(prompts)) != len(prompts):
        raise ValueError("Duplicate user prompts found across the Colab training sources")
    args.output.parent.mkdir(parents=True, exist_ok=True)
    temporary = args.output.with_name(f".{args.output.name}.{os.getpid()}.tmp")
    with temporary.open("w", encoding="utf-8", newline="\n") as stream:
        for row in rows:
            stream.write(json.dumps(row, ensure_ascii=False) + "\n")
    temporary.replace(args.output)
    print(json.dumps({
        "output": str(args.output),
        "general_examples": sum(row["source"] == "pc_sft" for row in rows),
        "correction_examples": sum(row["source"] == "pc_safety_v12" for row in rows),
        "total_examples": len(rows),
        "unique_user_prompts": len(set(prompts)),
    }, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
