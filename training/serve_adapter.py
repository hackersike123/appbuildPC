"""Local OpenAI-compatible inference server for the trained multimodal adapter."""

import argparse
import base64
import io
import threading
import time
import uuid
from pathlib import Path
from typing import Any

import torch
from fastapi import FastAPI, HTTPException
from peft import PeftModel
from PIL import Image
from transformers import AutoModelForMultimodalLM, AutoProcessor, BitsAndBytesConfig


MODEL_ID = "Qwen/Qwen3.5-2B"
ADAPTER_DIR = "training/output/pcbuild-qwen3.5-2b-qlora-v5"
DEFAULT_MODEL_NAME = "pcbuild-qwen3.5-2b-lora-v5"
MODEL_NAME = DEFAULT_MODEL_NAME
PC_DETECTOR_PATH = Path(__file__).parent / "output" / "pcbuild-pcparts-yolo26n" / "weights" / "best.pt"
app = FastAPI(title="PCBUILD Local AI", docs_url=None, redoc_url=None)
model = None
processor = None
detector_model = None
generation_lock = threading.Lock()
detector_lock = threading.Lock()


def load_model() -> None:
    global model, processor
    if not torch.cuda.is_available():
        raise RuntimeError("A CUDA GPU is required to serve the QLoRA adapter.")
    capability_major, _ = torch.cuda.get_device_capability(0)
    use_bf16 = torch.cuda.is_bf16_supported() and capability_major >= 8
    compute_dtype = torch.bfloat16 if use_bf16 else torch.float16
    gpu_gib = torch.cuda.get_device_properties(0).total_memory / (1024 ** 3)
    quantization = BitsAndBytesConfig(
        load_in_4bit=True,
        bnb_4bit_quant_type="nf4",
        bnb_4bit_use_double_quant=True,
        bnb_4bit_compute_dtype=compute_dtype,
    )
    base = AutoModelForMultimodalLM.from_pretrained(
        MODEL_ID,
        quantization_config=quantization,
        device_map="auto",
        max_memory={0: f"{max(5, int(gpu_gib * 0.90))}GiB", "cpu": "10GiB"},
        low_cpu_mem_usage=True,
        attn_implementation="sdpa",
    )
    model = PeftModel.from_pretrained(base, ADAPTER_DIR).eval()
    model.config.use_cache = True
    processor = AutoProcessor.from_pretrained(ADAPTER_DIR)


@app.on_event("startup")
def startup() -> None:
    load_model()
    load_pc_detector()


@app.get("/health")
def health():
    return {
        "ok": model is not None,
        "model": MODEL_NAME,
        "pcComponentDetector": detector_model is not None,
    }


@app.get("/v1/models")
def models():
    return {"object": "list", "data": [{"id": MODEL_NAME, "object": "model", "owned_by": "local"}]}


def _image_from_url(url: str) -> Image.Image:
    if not url.startswith("data:") or "," not in url:
        raise ValueError("Local AI accepts image data URLs from the app")
    encoded = url.split(",", 1)[1]
    raw = base64.b64decode(encoded, validate=True)
    if len(raw) > 8_000_000:
        raise ValueError("Image payload is too large")
    return Image.open(io.BytesIO(raw)).convert("RGB")


def _convert_messages(messages: list[dict[str, Any]]) -> list[dict[str, Any]]:
    converted = []
    for message in messages:
        role = str(message.get("role", "user"))
        content = message.get("content", "")
        if isinstance(content, str):
            converted.append({"role": role, "content": content})
            continue
        parts = []
        if not isinstance(content, list):
            raise ValueError("Message content must be text or a list")
        for part in content:
            if not isinstance(part, dict):
                continue
            if part.get("type") == "text":
                parts.append({"type": "text", "text": str(part.get("text", ""))})
            elif part.get("type") == "image_url":
                image_url = part.get("image_url", {}).get("url", "")
                parts.append({"type": "image", "image": _image_from_url(str(image_url))})
        converted.append({"role": role, "content": parts})
    return converted


def load_pc_detector() -> None:
    global detector_model
    if not PC_DETECTOR_PATH.is_file():
        return
    try:
        from ultralytics import YOLO

        detector_model = YOLO(str(PC_DETECTOR_PATH))
        detector_model.to("cpu")
    except Exception as error:
        print(f"PC component detector not loaded: {error}", flush=True)
        detector_model = None


def _component_detector_hint(image: Image.Image) -> str:
    if detector_model is None:
        return ""
    aliases = {
        "cpu": "CPU", "processor": "CPU", "mainboard": "MAINBOARD", "motherboard": "MAINBOARD", "mboard": "MAINBOARD",
        "gpu": "GPU", "graphics card": "GPU", "video card": "GPU", "vga": "GPU",
        "ram": "RAM", "memory": "RAM", "ram stick": "RAM", "memory module": "RAM",
        "ssd": "SSD", "solid state drive": "SSD", "storage": "STORAGE", "disk drive": "STORAGE",
        "hdd": "STORAGE", "hard disk": "STORAGE", "hard disk drive": "STORAGE",
        "psu": "PSU", "power supply": "PSU", "power supply unit": "PSU",
        "case": "CASE", "pc case": "CASE", "computer case": "CASE", "chassis": "CASE",
        "cooler": "COOLER", "cpu cooler": "COOLER", "heatsink": "COOLER", "heat sink": "COOLER",
    }
    try:
        with detector_lock:
            results = detector_model.predict(source=image, conf=0.25, verbose=False, device="cpu")
        best_by_component: dict[str, float] = {}
        for result in results:
            names = result.names
            if result.boxes is None:
                continue
            for box in result.boxes:
                class_id = int(box.cls[0].item())
                class_name = names.get(class_id, str(class_id)) if isinstance(names, dict) else names[class_id]
                component = aliases.get(" ".join(str(class_name).lower().replace("_", " ").split()))
                confidence = float(box.conf[0].item())
                if component and confidence >= 0.25:
                    best_by_component[component] = max(confidence, best_by_component.get(component, 0.0))
        if not best_by_component:
            return ""
        found = ", ".join(f"{name} ({score:.2f})" for name, score in sorted(best_by_component.items()))
        return (
            "Gợi ý loại linh kiện từ bộ dò hình ảnh PC local đã train: "
            f"{found}. Đây chỉ là loại linh kiện và không phải xác nhận SKU; "
            "hãy tự đọc ảnh và đối chiếu catalog SQL trước khi trả productId."
        )
    except Exception as error:
        print(f"PC component detection skipped: {error}", flush=True)
        return ""


def _add_detector_hints(messages: list[dict[str, Any]]) -> None:
    for message in messages:
        content = message.get("content")
        if message.get("role") != "user" or not isinstance(content, list):
            continue
        hints = [
            _component_detector_hint(part["image"])
            for part in content
            if isinstance(part, dict) and part.get("type") == "image" and isinstance(part.get("image"), Image.Image)
        ]
        for hint in filter(None, hints):
            content.insert(0, {"type": "text", "text": hint})


@app.post("/v1/chat/completions")
def chat_completions(body: dict[str, Any]):
    if model is None or processor is None:
        raise HTTPException(status_code=503, detail="Local PC model is still loading")
    try:
        messages = _convert_messages(body.get("messages", []))
        _add_detector_hints(messages)
        inputs = processor.apply_chat_template(
            messages,
            tokenize=True,
            add_generation_prompt=True,
            return_dict=True,
            return_tensors="pt",
        )
    except Exception as error:
        raise HTTPException(status_code=422, detail=str(error)) from error

    input_device = model.get_input_embeddings().weight.device
    inputs = inputs.to(input_device)
    max_tokens = min(max(int(body.get("max_tokens", 512)), 1), 1024)
    temperature = float(body.get("temperature", 0.4))
    generation = {
        "max_new_tokens": max_tokens,
        "do_sample": temperature > 0,
        "temperature": max(temperature, 0.01),
        "top_p": min(max(float(body.get("top_p", 0.8)), 0.01), 1.0),
        "top_k": 20,
        "repetition_penalty": 1.0,
        "pad_token_id": processor.tokenizer.pad_token_id or processor.tokenizer.eos_token_id,
    }
    with generation_lock, torch.inference_mode():
        output = model.generate(**inputs, **generation)
    reply = processor.decode(
        output[0, inputs["input_ids"].shape[-1]:],
        skip_special_tokens=True,
        clean_up_tokenization_spaces=False,
    ).strip()
    if not reply:
        raise HTTPException(status_code=502, detail="Local model returned an empty response")
    prompt_tokens = int(inputs["input_ids"].shape[-1])
    completion_tokens = int(output.shape[-1] - prompt_tokens)
    return {
        "id": f"chatcmpl-{uuid.uuid4().hex}",
        "object": "chat.completion",
        "created": int(time.time()),
        "model": MODEL_NAME,
        "choices": [{
            "index": 0,
            "message": {"role": "assistant", "content": reply},
            "finish_reason": "stop",
        }],
        "usage": {
            "prompt_tokens": prompt_tokens,
            "completion_tokens": completion_tokens,
            "total_tokens": prompt_tokens + completion_tokens,
        },
    }


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=3107)
    parser.add_argument("--model", default=MODEL_ID)
    parser.add_argument("--adapter", type=Path, default=Path(ADAPTER_DIR))
    parser.add_argument("--model-name", default=None)
    args = parser.parse_args()
    MODEL_ID = args.model
    ADAPTER_DIR = args.adapter
    MODEL_NAME = args.model_name or (
        DEFAULT_MODEL_NAME
        if args.adapter == Path("training/output/pcbuild-qwen3.5-2b-qlora-v5")
        else args.adapter.name
    )
    import uvicorn

    uvicorn.run(app, host=args.host, port=args.port, workers=1)
