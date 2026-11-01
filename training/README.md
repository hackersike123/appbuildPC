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
  epoch 1 nhưng dừng trước khi hoàn tất; checkpoint nằm tại
  `training/output/pcbuild-qwen3.5-2b-qlora-v12/checkpoint-12`. Checkpoint cũ
  không ghi fingerprint dữ liệu và cấu hình đầy đủ để xác nhận resume an toàn.
  Workflow Colab mới bắt đầu lại từ adapter v11 với tập general hiện tại và
  corrective v12, lưu vào run riêng; checkpoint v12 cũ được giữ nguyên để tham
  khảo, chưa được đánh giá hoặc triển khai.
- V13 đã train trên Google Colab T4 ngày 2026-10-26: 2 epochs, 102 bước, FP16,
  từ v11 trên 255 JSONL nguồn (231 ví dụ còn assistant token sau encoding; 203
  train/28 validation). Train loss `1.659`, validation loss `1.686`. Adapter,
  checkpoint, log và metric nằm trên Drive tại
  `MyDrive/PCBUILD/runs/pcbuild-qwen3.5-2b-qlora-v13-colab/`.
- V14 đã tiếp tục từ v13 trên T4: 6 epochs, 306 bước, train loss `1.516`,
  validation loss tốt nhất `1.5864` so với v13 `1.6861`. Run hoàn tất bình thường;
  adapter và `training_metrics.json` đã được ghi tại
  `MyDrive/PCBUILD/runs/pcbuild-qwen3.5-2b-qlora-v14-colab/checkpoints/final/`.
  Run chọn checkpoint theo validation và không dùng lại behavioral held-out 11
  ca. Bộ test độc lập mới vẫn cần thiết trước khi cân nhắc tích hợp.
- V15 đã tiếp tục từ v14 với micro-batch 2, accumulation 2 (effective batch 4),
  6 epochs/306 bước. Train loss `1.609`, validation loss `1.6381`, tốc độ
  `0.15` bước/giây; VRAM quan sát được khoảng `10.2/15 GiB`. V15 không vượt v14,
  nên giữ v14 làm ứng viên tốt nhất; v15 vẫn được lưu để đối chiếu tại
  `MyDrive/PCBUILD/runs/pcbuild-qwen3.5-2b-qlora-v15-colab/checkpoints/final/`.
- Không dùng hội thoại, ảnh scan hay dữ liệu tài khoản riêng để train.
- Hạn chế: adapter cập nhật lớp ngôn ngữ; vision encoder chưa fine-tune trên ảnh
  linh kiện thật có nhãn. Chưa có đánh giá độ chính xác tổng quát trên ảnh sản phẩm.

SQL/backend vẫn là nguồn có thẩm quyền cho giá, catalog, thông số, công suất,
tương thích và dữ liệu người dùng. Model diễn giải câu hỏi và dữ liệu backend cấp;
không thay thế các phép kiểm tra nghiệp vụ.

## Kết quả đánh giá đã ghi nhận

Các kết quả 7/7 và 5/5 dưới đây là số liệu lịch sử của các lượt đánh giá trước;
không phải kết quả behavioral test của v18. V18 đã cải thiện validation trên
cùng split nhưng held-out test riêng vẫn đang chờ chạy.

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
- Đánh giá deterministic trên 11 ca: baseline v11 `7/11`, candidate v13 `7/11`,
  không làm hỏng ca baseline đã đạt nhưng vẫn trượt cáp modular PSU, mùi khét,
  BIOS mainboard và DDR5 memory training. V13 không đủ điều kiện triển khai.

## Môi trường huấn luyện

Workflow ưu tiên trên Google Colab được mô tả bên dưới. Script local vẫn được
giữ để chạy/eval ngoại tuyến nếu muốn; không cần dựng môi trường local để dùng
notebook Colab.

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

Có thể chọn base model và adapter khác để đánh giá; ví dụ với v18 sau khi đã
đưa adapter từ Drive về thư mục cục bộ:

```powershell
.\.venv-ai-training\Scripts\python.exe training\evaluate_adapter.py `
  --base-model Qwen/Qwen3.5-4B `
  --adapter "training\output\pcbuild-qwen3.5-4b-qlora-v18\final" `
  --output "training\output\pcbuild-qwen3.5-4b-qlora-v18\qualitative_eval.json"

.\.venv-ai-training\Scripts\python.exe training\serve_adapter.py `
  --model Qwen/Qwen3.5-4B `
  --adapter "training\output\pcbuild-qwen3.5-4b-qlora-v18\final" `
  --model-name pcbuild-qwen3.5-4b-qlora-v18 --host 127.0.0.1 --port 3107
```

Server chọn FP16/BF16 và giới hạn VRAM theo GPU; endpoint vẫn chỉ dành cho đánh
giá local, không tự đổi provider của app.

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

## Google Colab

Hai notebook tách riêng huấn luyện adapter ngôn ngữ và detector ảnh:

- [PCBUILD_Colab_QLoRA.ipynb](./PCBUILD_Colab_QLoRA.ipynb) gộp 203 ví dụ
  general hiện tại với 52 ví dụ corrective v12, kiểm tra prompt trùng, fine-tune
  2 epoch từ adapter v11, rồi so sánh baseline/candidate trên 11 ca hành vi cố
  định. Kết quả 11/11 chỉ đủ điều kiện review thủ công; notebook không tự đổi
  model runtime. Notebook đã chạy và lưu ở
  [Google Drive](https://colab.research.google.com/drive/1Z6UWxG-gQJPzmE0ZvAjpkhja1Cc9OFF_).
- [PCBUILD_Colab_QLoRA_Continue.ipynb](./PCBUILD_Colab_QLoRA_Continue.ipynb)
  tiếp tục từ v13, dùng early stopping theo validation loss và không gọi lại bộ
  behavioral held-out đã dùng để đánh giá v13.
- [PCBUILD_Colab_QLoRA_v15.ipynb](./PCBUILD_Colab_QLoRA_v15.ipynb) tiếp tục từ
  adapter v14 với micro-batch 2 và gradient accumulation 2, giữ effective batch
  4. Script mới giới hạn model placement ở khoảng 90% VRAM và 10 GiB CPU để chừa
  headroom; nếu T4 báo OOM, giảm micro-batch trong một run mới. Notebook nhận
  bundle qua VS Code Colab Explorer (`Upload to Colab`), xác minh SHA-256 rồi
  sao chép bundle vào Drive trước khi giải nén. Kết quả v15 không được chọn do
  validation kém hơn v14; v16 kiểm tra batch-size tối đa cho 2B và cũng không
  vượt v14. Theo yêu cầu train thêm ứng viên lớn hơn, v17 thử Qwen3.5-4B.
- [PCBUILD_Colab_QLoRA_v16.ipynb](./PCBUILD_Colab_QLoRA_v16.ipynb) đã train từ
  v14 với micro-batch 4, accumulation 1, effective batch 4. Lượt T4 hoàn tất
  6 epochs/306 bước không OOM; VRAM đạt khoảng `13.87/15 GiB` (~92%) và RAM hệ
  thống khoảng `4.4/12.67 GiB` (~35%). Validation loss tốt nhất `1.6272`, kém v14
  (`1.5864`), nên giữ v14 làm ứng viên tốt nhất. Micro-batch 4 đã gần giới hạn
  VRAM thực tế của T4; không tăng batch thêm. RAM hệ thống còn trống không cần
  ép sử dụng: tập dữ liệu đã encode nhỏ, dùng thêm RAM không làm train nhanh
  hơn. Muốn tăng chất lượng cần dữ liệu PC có nhãn và held-out test mới.
- [PCBUILD_Colab_QLoRA_v17.ipynb](./PCBUILD_Colab_QLoRA_v17.ipynb) train mới
  Qwen3.5-4B Instruct bằng QLoRA NF4 từ weights nền: 6 epochs/306 bước,
  micro-batch 1 × accumulation 4, learning rate `1e-5`. Train loss `1.2668`,
  validation loss `0.9822` (v14 2B: `1.5864`), runtime `4793` giây, tốc độ
  `0.064` bước/giây. VRAM quan sát khoảng `9.72/15 GiB`; adapter và metrics đã
  xác nhận tại `MyDrive/PCBUILD/runs/pcbuild-qwen3.5-4b-qlora-v17-colab/checkpoints/final/`.
  Đây là baseline 4B trước run v18, chưa phải xác nhận tổng quát hóa. Cần đánh
  giá behavior độc lập trước khi chọn bất kỳ adapter nào thay runtime.
- [PCBUILD_Colab_QLoRA_v18.ipynb](./PCBUILD_Colab_QLoRA_v18.ipynb) tiếp tục
  adapter v17 với micro-batch 2 × accumulation 2 (effective batch 4), learning
  rate `3e-6`. Sau khi quota Colab được cấp lại, run đã resume từ
  `checkpoint-40` trên T4 và kết thúc ở global step `160/306` (epoch `3.137`)
  theo early stopping. Dataset có 231 ví dụ sau encoding, gồm 203 train và 28
  validation. Run dùng FP16, QLoRA NF4 4-bit; train loss `0.7056`, best
  validation loss `0.8902`, train runtime `1789` giây (`0.067` bước/giây). V18
  thấp hơn v17 (`0.9822`) và v14 (`1.5864`) trên cùng split. Adapter tốt nhất,
  checkpoint và metrics được ghi tại
  `MyDrive/PCBUILD/runs/pcbuild-qwen3.5-4b-qlora-v18-mb2-colab/checkpoints/final/`;
  adapter v17 vẫn được giữ nguyên.
  So sánh này chỉ dùng validation split; v18 chưa chạy held-out behavioral
  test, vì vậy vẫn là ứng viên offline và chưa được tích hợp vào app.
- [PCBUILD_Colab_QLoRA_v20.ipynb](../PCBUILD_Colab_QLoRA_v20.ipynb) thử direct-answer
  refinement từ adapter v18. Lượt đầu với micro-batch 2 dừng ở bước 0/90 do
  CUDA OOM; không có checkpoint hoặc kết quả eval nên chưa được tính là run
  thành công. Bản retry dùng micro-batch 1 × accumulation 4 (effective batch 4),
  learning rate `2e-6`, tối đa 2 epochs, lưu vào thư mục Drive riêng và dừng sớm
  theo validation. Cell kiểm tra GPU và ít nhất 10 GiB VRAM trống trước khi cài thư viện/train.
  Notebook dùng 203 ví dụ general và 52 ví dụ corrective, thêm chỉ thị trả lời
  trực tiếp vào system prompt. Suffix có thể làm thay đổi ví dụ bị loại sau
  encode/truncation; notebook in số lượng encoded để đối chiếu, nhưng số lượng
  giống nhau không chứng minh validation membership giống hệt. Cần held-out
  behavioral evaluation riêng trước mọi quyết định dùng adapter. Phiên Colab
  gần nhất báo thiếu quota; v20 chưa train thành công, chưa có metric hay adapter.
- Có thể mở notebook QLoRA trong VS Code với extension Colab, nhưng phải chọn
  kernel Colab remote T4; kernel Python local không có `google.colab` hoặc
  Google Drive mount. Khi một run bị ngắt, kết nối lại runtime T4 và chạy các
  cell theo thứ tự. Cell train kiểm tra checkpoint Drive mới nhất và trạng thái
  checkpoint trước khi resume; nếu adapter cuối đã có metrics, cell sẽ bỏ qua
  train trùng. Cell so sánh validation không thay thế held-out behavioral test.
- [PCBUILD_Colab_Vision.ipynb](./PCBUILD_Colab_Vision.ipynb) yêu cầu dataset
  YOLO có train/val/test riêng cùng source/license. Repository hiện chưa có
  dataset phù hợp nên chưa train detector. Notebook đã lưu ở
  [Google Drive](https://colab.research.google.com/drive/1iIfipPRt4qfIJ4c8wOUcBqli61BRPadu).

Tạo gói source để upload lần đầu:

```powershell
py -3.11 training\make_colab_bundle.py --output "$env:TEMP\pcbuild-colab-bundle.zip"
```

Gói chỉ gồm script train/eval, JSONL synthetic hiện có và các file adapter v11
cần cho baseline; không chứa `.env`, thông tin tài khoản hay các checkpoint
khác. Upload notebook lên Colab đã đăng nhập, chọn GPU runtime, rồi upload gói
khi notebook yêu cầu. Notebook mount Google Drive và lưu dưới
`MyDrive/PCBUILD/runs/`. Train chạy trên ổ tạm Colab để nhanh; checkpoint QLoRA
được mirror mỗi 8 bước, log/heartbeat ghi mỗi bước, và notebook tự resume khi
chạy lại nếu fingerprint dữ liệu, seed adapter và cấu hình khớp. Detector lưu
`last.pt`, `best.pt`, log và metric trực tiếp trong Drive để resume theo epoch.

Không dùng paid LLM API, Hugging Face token hay tracker bên thứ ba. Colab vẫn
có thể giới hạn GPU/thời gian theo quota hoặc gói Google; model Qwen public được
tải từ Hugging Face. Adapter và detector tiếp tục là artifact offline, không
được nạp bởi app/backend hiện tại. Bộ 11 ca hành vi và held-out test của detector
không được dùng làm training data.

