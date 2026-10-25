"""Exercise the running backend's local chat and image-scan routes."""

import base64
import io
import json
import os
import sys
import urllib.error
import urllib.request
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont


BASE_URL = os.getenv("PCBUILD_API_BASE_URL", "http://127.0.0.1:3000").rstrip("/")


def request(path, payload=None, token=None, method=None):
    data = None if payload is None else json.dumps(payload).encode("utf-8")
    headers = {"content-type": "application/json"}
    if token:
        headers["authorization"] = f"Bearer {token}"
    req = urllib.request.Request(
        BASE_URL + path,
        data=data,
        headers=headers,
        method=method or ("POST" if payload is not None else "GET"),
    )
    try:
        with urllib.request.urlopen(req, timeout=180) as response:
            body = response.read()
            return response.status, json.loads(body) if body else None
    except urllib.error.HTTPError as error:
        body = error.read().decode("utf-8", errors="replace")
        raise RuntimeError(f"API {path} returned {error.code}: {body[:500]}") from error


def chat(token, prompt):
    _, result = request("/api/v1/ai/chat", {"messages": [{"role": "user", "content": prompt}]}, token)
    return str(result.get("choices", [{}])[0].get("message", {}).get("content", ""))


def make_label_image():
    image = Image.new("RGB", (1500, 700), "white")
    draw = ImageDraw.Draw(image)
    font_path = Path(r"C:\Windows\Fonts\arial.ttf")
    font = ImageFont.truetype(str(font_path), 58) if font_path.exists() else ImageFont.load_default()
    lines = [
        "ZOTAC GAMING",
        "GeForce RTX 3060",
        "Twin Edge OC",
        "12GB GDDR6",
    ]
    y = 80
    for line in lines:
        draw.text((70, y), line, fill="black", font=font)
        y += 135
    output = io.BytesIO()
    image.save(output, format="PNG")
    return base64.b64encode(output.getvalue()).decode("ascii")


def make_ambiguous_gpu_image():
    image = Image.new("RGB", (1500, 760), "white")
    draw = ImageDraw.Draw(image)
    font_path = Path(r"C:\Windows\Fonts\arial.ttf")
    font = ImageFont.truetype(str(font_path), 62) if font_path.exists() else ImageFont.load_default()
    lines = [
        "GEFORCE RTX 4060",
        "ASUS DUAL",
        "MSI VENTUS",
        "GIGABYTE WINDFORCE",
        "MODEL NUMBER NOT SHOWN",
    ]
    y = 55
    for line in lines:
        draw.text((55, y), line, fill="black", font=font)
        y += 135
    output = io.BytesIO()
    image.save(output, format="PNG")
    return base64.b64encode(output.getvalue()).decode("ascii")


def main():
    sys.stdout.reconfigure(encoding="utf-8")
    token = os.getenv("PCBUILD_TEST_TOKEN")
    email = os.getenv("PCBUILD_TEST_EMAIL")
    password = os.getenv("PCBUILD_TEST_PASSWORD")
    if token:
        try:
            request("/api/v1/auth/me", token=token)
        except RuntimeError:
            token = None
    if not token:
        if not email or not password:
            raise SystemExit("Set PCBUILD_TEST_TOKEN, or PCBUILD_TEST_EMAIL and PCBUILD_TEST_PASSWORD.")
        _, login = request("/api/v1/auth/login", {"email": email, "password": password})
        token = login["accessToken"]
    print("login=ok")

    _, builds = request("/api/v1/builds", token=token)
    if not builds:
        raise RuntimeError("The test account needs a saved SQL build to exercise the app's PSU context.")
    power = builds[0].get("powerAssessment") or {}
    psu_answer = chat(token, "Hãy nêu riêng tải ước tính, mức PSU hệ thống, mức hãng nếu có, PSU đã chọn và từng khoảng dư/thiếu của build hiện tại.")
    expected_load = power.get("estimatedLoadW")
    expected_system = power.get("recommendedPsuW")
    expected_selected = power.get("selectedPsuW")
    psu_ok = all(
        value is not None and f"{int(value)} w" in psu_answer.lower()
        for value in [expected_load, expected_system, expected_selected]
    )
    if power.get("manufacturerMinimumW") is None:
        psu_ok = psu_ok and any(term in psu_answer.lower() for term in ["chưa có mức psu hãng", "chưa đủ dữ liệu"])
    else:
        psu_ok = psu_ok and f"{int(power['manufacturerMinimumW'])} w" in psu_answer.lower()
    print(json.dumps({"case": "psu", "passed": psu_ok, "answer": psu_answer}, ensure_ascii=False))

    missing_price = chat(token, "Hãy cho giá SQL hiện tại của mã nonexistent-test-id-123; nếu không có bản ghi thì nói rõ.")
    price_ok = any(term in missing_price.lower() for term in ["không có bản ghi", "chưa có bản ghi", "không tìm thấy", "chưa có dữ liệu", "chưa thể xác nhận", "không thể xác nhận"])
    print(json.dumps({"case": "missing_sql_price", "passed": price_ok, "answer": missing_price}, ensure_ascii=False))

    scope = chat(token, "Viết bài đánh giá bộ phim tôi vừa xem.")
    scope_ok = any(term in scope.lower() for term in ["chỉ hỗ trợ pc", "chuyên hỗ trợ pc", "linh kiện pc", "cấu hình pc", "hỗ trợ cấu hình, linh kiện, nguồn và tương thích pc"])
    print(json.dumps({"case": "pc_scope", "passed": scope_ok, "answer": scope}, ensure_ascii=False))

    scan_id = None
    scan_result = None
    scan_ok = False
    try:
        status, scan_result = request(
            "/api/v1/ai/scan",
            {"imageBase64": make_label_image(), "imageMimeType": "image/png"},
            token,
        )
        scan_id = scan_result.get("id")
        scan_ok = status == 201 and scan_result.get("detectedProductId") == "gpu-3060-zotac"
        print(json.dumps({
            "case": "product_scan",
            "passed": scan_ok,
            "status": scan_result.get("status"),
            "detectedProductId": scan_result.get("detectedProductId"),
            "analysis": scan_result.get("analysis"),
        }, ensure_ascii=False))
    finally:
        if scan_id:
            request(f"/api/v1/scans/{scan_id}", token=token, method="DELETE")
            print("synthetic_scan_cleanup=ok")

    ambiguous_id = None
    ambiguous_ok = False
    try:
        _, ambiguous = request(
            "/api/v1/ai/scan",
            {"imageBase64": make_ambiguous_gpu_image(), "imageMimeType": "image/png"},
            token,
        )
        ambiguous_id = ambiguous.get("id")
        ambiguous_ok = ambiguous.get("detectedProductId") is None and ambiguous.get("status") == "unrecognized"
        print(json.dumps({
            "case": "ambiguous_scan",
            "passed": ambiguous_ok,
            "status": ambiguous.get("status"),
            "detectedProductId": ambiguous.get("detectedProductId"),
            "analysis": ambiguous.get("analysis"),
        }, ensure_ascii=False))
    finally:
        if ambiguous_id:
            request(f"/api/v1/scans/{ambiguous_id}", token=token, method="DELETE")
            print("ambiguous_scan_cleanup=ok")

    passed = sum([psu_ok, price_ok, scope_ok, scan_ok, ambiguous_ok])
    print(f"APP_SMOKE {passed}/5")
    if passed != 5:
        raise SystemExit(1)


if __name__ == "__main__":
    main()
