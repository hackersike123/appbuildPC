## GitHub clone/fork

Training scripts and documentation are included, but datasets, model weights, and checkpoints are excluded from this branch. They are optional and are not used by the app runtime. Provide your own licensed dataset and local checkpoint if you train.

# Huấn luyện AI PCBUILD

## Adapter lưu trữ, không dùng trong app hiện tại

Runtime hiện dùng LM Studio cho toàn bộ tác vụ AI. Các adapter và dữ liệu train
trong thư mục này được giữ lại để tiếp tục huấn luyện sau; `start-full-backend.bat`
không nạp adapter.

- Model nền: `Qwen/Qwen3.5-2B`.
- Adapter gần nhất từng dùng trước khi chuyển sang LM Studio:
  `training/output/pcbuild-qwen3.5-2b-qlora-v5`.
- Kiểu fine-tune: QLoRA NF4 4-bit; bản v5 tiếp tục từ v4 với learning rate
  `8e-6`, một epoch, train loss `0.689` và validation loss `0.814`.
- Bản v5 đã train trên 139 ví dụ tiếng Việt tổng hợp. V6 và v7 đạt 6/11; v8
  đạt 8/11; v9 đạt 8/11 và v10 đạt 6/11 trên các bộ đánh giá mở rộng, nên cả
  hai chưa được đưa vào app.
- V11 đã train tiếp từ v9 trên 48 ví dụ, 3 epochs, learning rate `2e-6`;
  validation loss cuối `1.756`. Đánh giá hành vi đạt `7/11`: các ca giá,
  tương thích, công suất và JSON scan đạt; còn lỗi về cáp modular, mùi khét,
  model/revision BIOS và DDR5 memory training. V11 chưa được đưa vào app.
- V12 dùng tập corrective 52 ví dụ. Lượt đầu đã lưu checkpoint 12/24 bước ở
  epoch 1 nhưng dừng trước validation cuối; checkpoint nằm tại
  `training/output/pcbuild-qwen3.5-2b-qlora-v12/checkpoint-12`. Đang tiếp tục
  từ checkpoint này thêm một epoch với learning rate `5e-7`; adapter tiếp nối
  sẽ lưu tại `training/output/pcbuild-qwen3.5-2b-qlora-v12-resumed`. Tính đến
  lượt tiếp nối từng đạt 3/12 bước. Tiến trình train hiện đã dừng; chưa có eval
  v12 và v5 cũng không được nạp trong runtime hiện tại. Có thể tiếp tục từ
  checkpoint khi sẵn sàng huấn luyện lại.
- Không dùng hội thoại, ảnh scan hay dữ liệu tài khoản riêng để train.
- Hạn chế: adapter cập nhật lớp ngôn ngữ; vision encoder chưa fine-tune trên ảnh
  linh kiện thật có nhãn. Chưa có đánh giá độ chính xác tổng quát trên ảnh sản phẩm.

SQL/backend vẫn là nguồn có thẩm quyền cho giá, catalog, thông số, công suất,
tương thích và dữ liệu người dùng. Model diễn giải câu hỏi và dữ liệu backend cấp;
không thay thế các phép kiểm tra nghiệp vụ.

## Kết quả đánh giá đã ghi nhận

- Bài đánh giá hành vi PC: `7/7` trường hợp.
- Smoke test qua API app: `5/5` trường hợp — tóm tắt PSU theo build SQL, từ chối
  đoán giá khi thiếu dữ liệu, giới hạn trợ lý vào chủ đề PC, scan SKU rõ và từ
  chối ảnh nhiều model mơ hồ.
- Bộ scan trên dùng ảnh tổng hợp, không chứng minh khả năng nhận diện trên ảnh
  linh kiện thật. Các bản ghi scan thử được xóa khỏi SQL sau kiểm tra.
- V6–v11 chưa được đưa vào app vì không vượt đầy đủ các ca an toàn và hồi quy.
  V12 chỉ được chọn nếu qua các ca kiểm tra được tăng cường, gồm cáp modular,
  mùi khét, BIOS đúng model/revision, memory training DDR5, JSON scan và các
  hồi quy về giá/công suất/tương thích.

## Môi trường huấn luyện

Môi trường `.venv-ai-training` dùng Python 3.11, PyTorch CUDA 12.8,
Transformers 5.20.2, PEFT 0.21.2, Accelerate 1.15.0, bitsandbytes 0.50.2,
FastAPI và Uvicorn. Trên máy đã có môi trường này; cài mới bằng:

```powershell
py -3.11 -m venv .venv-ai-training
.\.venv-ai-training\Scripts\python.exe -m pip install --upgrade pip
.\.venv-ai-training\Scripts\python.exe -m pip install torch==2.11.0 torchvision==0.26.0 --index-url https://download.pytorch.org/whl/cu128
.\.venv-ai-training\Scripts\python.exe -m pip install -r training\requirements.txt
```

Model nền được tải/cached từ Hugging Face Hub. Lần đầu có thể cần mạng và thời
gian tải đáng kể. Adapter, metrics và checkpoint nằm trong `training/output/`.

## Train và đánh giá lại

Chuẩn bị dữ liệu, train và đánh giá theo các script hiện có:

```powershell
.\.venv-ai-training\Scripts\python.exe training\prepare_dataset.py
.\.venv-ai-training\Scripts\python.exe training\train_qlora.py --epochs 3 --output training\output\pcbuild-qwen3.5-2b-qlora-v3
.\.venv-ai-training\Scripts\python.exe training\evaluate_adapter.py --adapter training\output\pcbuild-qwen3.5-2b-qlora-v3
```

Tiếp tục từ adapter v4:

```powershell
.\.venv-ai-training\Scripts\python.exe training\train_qlora.py --epochs 1 --learning-rate 8e-6 --init-adapter training\output\pcbuild-qwen3.5-2b-qlora-v4 --output training\output\pcbuild-qwen3.5-2b-qlora-v5
```

## Chạy adapter ngoại tuyến để đánh giá

Các lệnh dưới đây chỉ dành cho kiểm tra model trong môi trường train; app và
backend không gọi endpoint này.

```powershell
.\.venv-ai-training\Scripts\python.exe training\serve_adapter.py --host 127.0.0.1 --port 3107
Invoke-RestMethod http://localhost:3107/health
Invoke-RestMethod http://localhost:3107/v1/models
```

Adapter nhận văn bản và ảnh base64 để phục vụ đánh giá ngoại tuyến. Không cấu
hình endpoint này vào `backend/.env` hoặc public cổng `3107`.

## Train detector vision cho linh kiện PC

Detector object-detection là nhánh riêng với adapter ngôn ngữ Qwen. Script
`train_pc_vision.py` nhận dataset YOLO có ba split độc lập `train`, `val`, `test`
và nhãn hộp 5 trường. COCO có thể chuyển bằng `convert_coco_pc.py` nếu có ảnh
và annotation riêng cho cả ba split. Dataset phải có ít nhất bốn loại linh kiện PC được nhận
diện trong bộ alias: CPU, MAINBOARD, GPU, RAM, SSD/storage, PSU, CASE và COOLER.
Script từ chối train nếu không có tập test giữ riêng hoặc nhãn không hợp lệ.

Cài dependency vision riêng trong môi trường training:

```powershell
.\.venv-ai-training\Scripts\python.exe -m pip install -r training\vision-requirements.txt
```

Khi có dataset đã gán nhãn và quyền sử dụng phù hợp:

```powershell
.\.venv-ai-training\Scripts\python.exe training\convert_coco_pc.py `
  --train-json "C:\pcvision\annotations\instances_train.json" `
  --train-images "C:\pcvision\train" `
  --val-json "C:\pcvision\annotations\instances_val.json" `
  --val-images "C:\pcvision\val" `
  --test-json "C:\pcvision\annotations\instances_test.json" `
  --test-images "C:\pcvision\test" `
  --output training\data\pc-components-yolo

.\.venv-ai-training\Scripts\python.exe training\train_pc_vision.py `
  --data training\data\pc-components-yolo\data.yaml `
  --dataset-source "<nguon dataset>" `
  --dataset-license "<license>" `
  --model yolo26n.pt --epochs 80 --imgsz 640 --batch 8 --device 0
```

Kết quả held-out test và thông tin license được ghi trong
`training/output/pcbuild-pcparts-yolo26n/vision_metrics.json`; trọng số tốt nhất
được lưu tại `training/output/pcbuild-pcparts-yolo26n/weights/best.pt`. `serve_adapter.py`
sẽ tự nạp detector này trên CPU và đưa loại linh kiện dự đoán cho Qwen làm gợi ý;
Qwen vẫn phải đọc ảnh và catalog SQL để xác nhận SKU. Nếu file trọng số chưa có,
app tiếp tục dùng model ảnh nền Qwen.

Hiện trong repository chỉ có ba ảnh minh họa GPU và không có nhãn detection cho
CPU/mainboard/RAM/SSD/PSU/case/tản nhiệt. Chưa train detector đa loại từ các ảnh
đó vì tập đó không đủ đại diện và sẽ dễ học thuộc ảnh GPU thay vì nhận diện linh
kiện PC tổng quát. Hãy cung cấp dataset YOLO/COCO có nhãn và license rõ để chạy
training thật.
