"""Qualitative PCBUILD behavior checks for a local Qwen3.5 LoRA adapter."""

import argparse
import json
import re
import sys
from pathlib import Path

import torch
from peft import PeftModel
from transformers import AutoModelForMultimodalLM, AutoProcessor, BitsAndBytesConfig


ROOT = Path(__file__).parent
DATA = ROOT / "data" / "pc_sft.jsonl"
BASE = "Qwen/Qwen3.5-2B"
DEFAULT_ADAPTER = ROOT / "output" / "pcbuild-qwen3.5-2b-qlora-v3"

CASES = [
    {
        "name": "psu_margin",
        "prompt": "SQL powerAssessment: {\"estimatedLoadW\":235,\"manufacturerMinimumW\":600,\"recommendedPsuW\":600,\"selectedPsuW\":650,\"marginW\":50,\"marginFromLoadW\":415,\"marginVsManufacturerW\":50}. Hãy nêu tải, mức hãng, PSU chọn và dư/thiếu theo hãng.",
        "required": ["235 W", "600 W", "650 W", "dư 50 W"],
        "forbidden": ["thiếu 350 W", "thiếu 50 W"],
    },
    {
        "name": "psu_shortfall",
        "prompt": "powerAssessment: {\"estimatedLoadW\":220,\"manufacturerMinimumW\":450,\"recommendedPsuW\":450,\"selectedPsuW\":400,\"marginW\":-50,\"marginFromLoadW\":180,\"marginVsManufacturerW\":-50}. Hãy báo cáo đúng các số này.",
        "required": ["220 W", "450 W", "400 W", "thiếu 50 W"],
    },
    {
        "name": "unknown_manufacturer_floor",
        "prompt": "powerAssessment: {\"estimatedLoadW\":235,\"manufacturerMinimumW\":null,\"recommendedPsuW\":450,\"selectedPsuW\":550,\"marginW\":100,\"marginFromLoadW\":315,\"marginVsManufacturerW\":null}. Mức hãng SQL chưa có. Nguồn đạt theo hãng không?",
        "required_any": [["chưa có", "chưa đủ dữ liệu"]],
        "forbidden": ["đạt khuyến nghị hãng", "đủ theo tải", "100 w dư so với mức hãng", "so với mức hãng khuyến nghị: 100w dư"],
        "forbidden_regex": [
            r"mức\s+psu\s+hãng[^.\n]*\d+\s*w",
            r"so\s+với\s+mức\s+hãng[^.\n]*\d+\s*w",
            r"khuyến\s+nghị\s+(?:tối\s+thiểu\s+)?(?:của\s+)?hãng[^.\n]*\d+\s*w",
        ],
    },
    {
        "name": "socket_mismatch",
        "prompt": "CPU socket AM5, mainboard socket LGA1700; RAM và PSU chưa chọn. Báo cáo tương thích.",
        "required_any": [["chưa tương thích", "không tương thích", "socket khác"]],
    },
    {
        "name": "missing_sql_price",
        "prompt": "Giá RTX 4060 hôm nay bao nhiêu nếu ngữ cảnh SQL không có bản ghi giá?",
        "required_any": [["không có bản ghi", "chưa có bản ghi giá", "chưa có giá sql", "chưa thể xác nhận giá", "không thể xác nhận giá"]],
    },
    {
        "name": "ambiguous_scan_json",
        "prompt": "Quét ảnh: tem mờ, không phân biệt được hai SKU GPU gần giống trong catalog. Trả duy nhất JSON với recognized, productId, componentType, confidence, summary.",
        "scan": {"recognized": False, "productId": None},
    },
    {
        "name": "exact_scan_catalog_id",
        "prompt": "Quét ảnh: tem đọc rõ Zotac RTX 3060 Twin Edge, catalog xác nhận đúng id gpu-3060-zotac. Trả duy nhất JSON với recognized, productId, componentType, confidence, summary.",
        "scan": {"recognized": True, "productId": "gpu-3060-zotac"},
    },
    {
        "name": "modular_psu_cable_safety",
        "prompt": "Dây modular của PSU cũ cùng hãng có dùng cho PSU mới được không?",
        "required_any": [
            ["không dùng", "đừng dùng", "không cắm", "không nên dùng"],
            ["pinout", "sơ đồ chân"],
            ["model", "sku"],
            ["hãng xác nhận", "nhà sản xuất xác nhận", "tài liệu chính hãng", "dây đi kèm nguồn mới", "psu mới"],
        ],
        "forbidden": ["cứ cắm được", "dùng thoải mái", "thử cắm", "cắm thử"],
    },
    {
        "name": "burning_smell_power_safety",
        "prompt": "PC có mùi khét và tiếng tách điện nhưng vẫn chạy. Tôi tiếp tục dùng không?",
        "required_any": [
            ["rút điện", "ngắt điện", "ngắt nguồn"],
            ["không bật lại", "không cấp điện lại", "không bật máy lại"],
            ["kỹ thuật viên", "bảo hành", "thợ"],
        ],
        "forbidden": [
            "tiếp tục dùng bình thường",
            "chờ 15 phút rồi thử",
            "chờ vài phút rồi bật lại",
            "bật lại để thử",
            "cắm lại thử",
        ],
    },
    {
        "name": "bios_board_specific_caution",
        "prompt": "Tôi muốn BIOS để hỗ trợ CPU mới, mainboard chưa rõ model. Đưa đúng file cho tôi.",
        "required_any": [
            ["chưa thể", "không thể", "chưa xác định"],
            ["model mainboard", "model bo mạch", "model của mainboard", "mã mainboard", "mã bo mạch"],
            ["revision", "rev"],
            ["manual", "trang hỗ trợ", "tài liệu chính hãng", "nhà sản xuất", "hãng"],
            ["không đoán", "không flash", "không dùng file"],
        ],
        "forbidden": ["model cpu chính xác", "mã cpu chính xác", "số seri cpu"],
    },
    {
        "name": "ram_training_first_boot",
        "prompt": "Máy DDR5 đứng lâu ở lần khởi động đầu sau khi lắp RAM. Có nên cắt điện?",
        "required_any": [
            ["chờ", "đợi"],
            ["memory training", "training ram", "training bộ nhớ", "đèn post"],
            ["manual", "hướng dẫn của mainboard", "hướng dẫn hãng", "nhà sản xuất"],
        ],
        "forbidden": [
            "cắt điện ngay",
            "rút điện ngay",
            "cắt điện liên tục",
            "tháo ram khi máy đang bật",
            "mở psu",
            "bật psu",
            "chờ 15 phút để ram xả",
        ],
    },
]


def normalize(text: str) -> str:
    text = re.sub(r"\s+", " ", text.lower())
    return re.sub(r"(?<=\d)\s+w\b", "w", text)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--adapter", type=Path, default=DEFAULT_ADAPTER)
    parser.add_argument("--max-new-tokens", type=int, default=220)
    parser.add_argument("--output", type=Path, default=None, help="Optional evaluation report path")
    args = parser.parse_args()
    sys.stdout.reconfigure(encoding="utf-8")

    with (DATA).open(encoding="utf-8") as f:
        system = json.loads(next(f))["messages"][0]["content"]
    processor = AutoProcessor.from_pretrained(args.adapter)
    quantization = BitsAndBytesConfig(
        load_in_4bit=True,
        bnb_4bit_quant_type="nf4",
        bnb_4bit_use_double_quant=True,
        bnb_4bit_compute_dtype=torch.bfloat16,
    )
    model = AutoModelForMultimodalLM.from_pretrained(
        BASE,
        quantization_config=quantization,
        device_map="auto",
        max_memory={0: "5.3GiB", "cpu": "7GiB"},
        low_cpu_mem_usage=True,
        attn_implementation="sdpa",
    )
    model = PeftModel.from_pretrained(model, args.adapter).eval()
    device = model.get_input_embeddings().weight.device
    results = []
    for case in CASES:
        messages = [
            {"role": "system", "content": system},
            {"role": "user", "content": case["prompt"]},
        ]
        inputs = processor.apply_chat_template(
            messages, tokenize=True, add_generation_prompt=True,
            return_dict=True, return_tensors="pt"
        ).to(device)
        with torch.inference_mode():
            generated = model.generate(
                **inputs,
                max_new_tokens=args.max_new_tokens,
                do_sample=True,
                temperature=0.7,
                top_p=0.8,
                top_k=20,
                repetition_penalty=1.0,
            )
        answer = processor.decode(
            generated[0, inputs["input_ids"].shape[-1]:],
            skip_special_tokens=True,
            clean_up_tokenization_spaces=False,
        ).strip()
        lower = normalize(answer)
        checks = [all(normalize(term) in lower for term in case.get("required", []))]
        checks.extend(any(normalize(term) in lower for term in group) for group in case.get("required_any", []))
        checks.extend(normalize(term) not in lower for term in case.get("forbidden", []))
        checks.extend(re.search(pattern, lower, flags=re.IGNORECASE) is None for pattern in case.get("forbidden_regex", []))
        if "scan" in case:
            parsed = None
            match = re.search(r"\{.*\}", answer, flags=re.DOTALL)
            if match:
                try:
                    parsed = json.loads(match.group(0))
                except json.JSONDecodeError:
                    pass
            expected = case["scan"]
            checks.append(isinstance(parsed, dict) and all(parsed.get(k) == v for k, v in expected.items()))
        result = {"name": case["name"], "passed": bool(checks) and all(checks), "checks": checks, "answer": answer}
        results.append(result)
        print(json.dumps(result, ensure_ascii=False))

    summary = {"passed": sum(x["passed"] for x in results), "total": len(results), "results": results}
    output = args.output or args.adapter / "qualitative_eval.json"
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(summary, ensure_ascii=False, indent=2), encoding="utf-8")
    print(f"\nQUALITATIVE {summary['passed']}/{summary['total']} -> {output}")


if __name__ == "__main__":
    main()
