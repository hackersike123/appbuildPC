# PCBUILD LOCAL

Ứng dụng Flutter cho Web và Android để xây cấu hình PC, xem giá theo khu vực,
kiểm tra tương thích, lưu build theo tài khoản, quét linh kiện và hỏi trợ lý PC.

## Kiến trúc

```text
Flutter Web / Android
        | REST + JWT
        v
Node.js API :3000 ------> SQL Server từ xa
        |
        +---------------> LM Studio (chat, scan, AI Build fallback)
```

- Flutter gọi API Node.js; client không kết nối trực tiếp tới SQL hoặc model AI.
- Backend dùng SQL Server làm nguồn dữ liệu cho tài khoản, catalog, giá, build,
  lịch sử quét và thông báo. `backend/data.json` chỉ còn phục vụ dữ liệu migration cũ.
- Nếu một linh kiện chưa có giá khu vực trong `dbo.market`, app hiển thị giá
  catalog ước tính từ `dbo.products.price` với nhãn riêng. Giá ước tính không
  được dùng làm biến động, lịch sử hoặc cảnh báo giá thị trường.
- Chat, tư vấn và nhận diện ảnh đều chạy trên LM Studio với prompt chuyên
  PCBUILD. AI Build dùng dữ liệu SQL; nếu không ghép được bằng luật tương thích,
  LM Studio chọn phương án dự phòng từ catalog SQL rút gọn.
- Model tự huấn luyện không được nạp hoặc gọi trong app/backend hiện tại; adapter
  và tập train được giữ lại để huấn luyện sau này trên phần cứng phù hợp.

## Chức năng

- Tài khoản, đăng nhập JWT, khôi phục mật khẩu qua SMTP.
- Chọn CPU, mainboard, GPU, RAM, SSD, PSU, case và tản nhiệt.
- Tính tổng giá theo khu vực; phân tích tương thích từ hai linh kiện trở lên;
  linh kiện còn thiếu không ngăn việc kiểm tra.
- Kiểm tra PSU với tải ước tính, mức đề nghị, PSU đã chọn và watt dư/thiếu.
- Tự kiểm tra tương thích lại sau khi thêm hoặc gỡ linh kiện; hiện cảnh báo,
  lý do và linh kiện thay thế ngay trong trang build.
- Tạo, lưu, mở, cập nhật, nhân bản và xóa build theo tài khoản.
- Vào mục So giá để chọn 2–3 món, dùng nút so sánh cố định và xem giá/lịch sử
  trực quan. Có thể quản lý cảnh báo giá.
- Lưu lịch sử quét vào SQL; linh kiện nhận diện được có thể tạo build nháp.
- Hoạt ảnh mô hình lắp ráp PC theo linh kiện đã chọn.

## Yêu cầu

- Windows, Flutter stable, Dart và Android SDK nếu chạy Android.
- Chrome/Edge nếu chạy Web.
- Node.js 20+ và dependencies trong `backend/node_modules`.
- LM Studio với model đã tải và Local Server khớp `backend/.env` để chạy các tác vụ AI.
- Python 3.11 và môi trường `.venv-ai-training` chỉ cần nếu huấn luyện/eval sau này.
- Truy cập được SQL Server đã cấu hình trong `backend/.env`.
- GPU phù hợp được khuyến nghị cho các phiên train trong tương lai; app hiện tại
  không nạp model QLoRA.

## Cài đặt lần đầu

Tại thư mục gốc:

```powershell
flutter pub get
```

```powershell
cd backend
npm install
```

Tạo `backend/.env` từ [backend/.env.example](./backend/.env.example), rồi điền
thông tin SQL/JWT và cấu hình LM Studio. Không đưa `.env` hoặc secret vào Git.
Môi trường train được tách riêng; xem [training/README.md](./training/README.md)
nếu cần tiếp tục huấn luyện model ngoài luồng chạy ứng dụng.

## Công cụ phát triển VS Code/Codex

- Mở **Extensions: Show Recommended Extensions** trong VS Code để cài Flutter/Dart, Python/Pylance, SQL Server, REST Client, PowerShell và YAML tooling được khai báo trong `.vscode/extensions.json`.
- `.vscode/mcp.json` cung cấp Context7 để tra tài liệu và DBHub để duyệt SQL Server. DBHub chỉ cho phép truy vấn đọc, giới hạn tối đa 200 dòng và lấy thông tin kết nối từ `backend/.env` qua launcher cục bộ; không ghi chuỗi kết nối vào cấu hình. DBHub cần Node.js 22.5+, trong khi backend riêng vẫn hỗ trợ Node.js 20+.
- Codex đọc hướng dẫn dự án từ `AGENTS.md`, skill từ `.agents/skills/`, agent profiles từ `.codex/agents/` và hook từ `.codex/hooks.json`. Hook chặn ba migration cũ không tương thích runtime; lệnh `ensure_schema.js` chỉ nhận nhắc nhở kiểm tra DB đích.
- Plugin `pcbuild-context7` đóng gói skill tra tài liệu và MCP Context7. Để cài cho người dùng Codex khác trong workspace, chạy `codex plugin marketplace add ./` tại thư mục gốc, sau đó `codex plugin add pcbuild-context7@pcbuild-project-tools`. Endpoint Context7 có thể dùng không cần API key; API key miễn phí tăng hạn mức.
- Codex yêu cầu duyệt/trust hook lần đầu qua `/hooks`. Chỉ trust hook sau khi xem nội dung `.codex/hooks.json` và `.codex/hooks/db-script-guard.cjs`.

## Khởi động toàn bộ backend trên Windows

Chạy file [start-full-backend.bat](./start-full-backend.bat) từ Explorer hoặc
PowerShell tại thư mục dự án:

```powershell
.\start-full-backend.bat
```

Launcher kiểm tra SQL rồi mở Node API ở cổng `3000`. Nạp model trong LM Studio
riêng và cấu hình `LM_STUDIO_URL`, `LM_STUDIO_MODEL` cùng
`LM_STUDIO_VISION_MODEL` trong `backend/.env`. Launcher không nạp model tự train.

Kiểm tra trạng thái:

```powershell
Invoke-RestMethod http://localhost:3000/health
```

API docs: <http://localhost:3000/docs> · OpenAPI:
<http://localhost:3000/openapi.json>

SQL Server là máy chủ từ xa nên không cần bật dịch vụ SQL cục bộ. Khi khởi động,
API tự đảm bảo schema tính năng cần thiết. Chỉ chạy
`node backend/ensure_schema.js` khi tạo database mới hoặc chủ động chuẩn bị
schema; không chạy các migration JSON cũ lên database runtime hiện tại.

LM Studio là provider AI duy nhất của ứng dụng. Catalog, giá, lịch sử giá, build
SQL và kiểm tra tương thích vẫn truy vấn SQL; tác vụ tạo câu trả lời, nhận diện
ảnh và build dự phòng dùng model LM Studio theo prompt riêng của PCBUILD.

### Khởi động thủ công

```powershell
cd backend
npm start
```

## Chạy Flutter

Chỉ cần chạy Flutter khi muốn mở client; backend không tự mở giao diện.

Chrome trên cùng máy:

```powershell
flutter run -d chrome --dart-define=API_BASE_URL=http://localhost:3000
```

Android Emulator trên cùng máy:

```powershell
flutter devices
flutter run -d <emulator-id> --dart-define=API_BASE_URL=http://10.0.2.2:3000
```

Điện thoại thật cần gọi được địa chỉ LAN của máy backend, ví dụ
`http://<IP-may-tinh>:3000`, hoặc URL HTTPS của tunnel. Không dùng `localhost`
trên điện thoại; cần cho phép kết nối qua firewall nếu dùng LAN. Backend gọi
model qua endpoint `LM_STUDIO_URL` trong cấu hình backend.

## Dữ liệu và giới hạn AI

Adapter v5 được fine-tune bằng ví dụ PC tổng hợp và hiện là bản đang phục vụ app.
V9 đạt 8/11, v10 đạt 6/11 và v11 đạt 7/11 trên bộ đánh giá mở rộng nên chưa
được triển khai. V12 tập trung sửa bốn lỗi an toàn; lượt train đầu dừng ở
12/24 bước, hiện tiếp tục từ checkpoint lưu sẵn (3/12 bước ở lần cập nhật gần
nhất). Chỉ thay model đang chạy nếu vượt toàn bộ đánh giá. Vision encoder
chưa được fine-tune bằng ảnh linh kiện thật có nhãn. Detector YOLO riêng cần
dataset ảnh linh kiện đã gán nhãn và tập test độc lập trước khi train/bật.
SQL là nguồn dữ liệu có thẩm quyền cho giá, thông số, tương thích, công suất và
dữ liệu tài khoản. Giá catalog ước tính được phân biệt với giá khu vực; biểu đồ
và cảnh báo chỉ dùng giá có trong `dbo.market`. Biểu đồ không tự bịa điểm lịch sử:
dữ liệu được tích lũy khi API ghi nhận giá theo thời gian.

Chi tiết về tập dữ liệu, train, đánh giá và cách chạy adapter ở
[training/README.md](./training/README.md). API, SQL, Swagger và SMTP được mô tả
trong [backend/README.md](./backend/README.md).

## Kiểm tra và build

```powershell
flutter analyze
flutter test
flutter build web
flutter build apk --debug
```

```powershell
cd backend
npm test
node --check server.js
```

Theo kết quả gần nhất được ghi nhận: Flutter analyze sạch, Flutter có 19 test
đạt; backend có 4 test đạt. AI hành vi đạt 7/7 và smoke test API với tài khoản
kiểm thử đạt 5/5. Bộ smoke scan dùng ảnh tổng hợp, chưa đại diện cho ảnh sản phẩm
thật.

## Cấu trúc chính

```text
lib/                         Flutter UI, điều hướng và dịch vụ client
backend/server.js            REST API và điều phối LM Studio
backend/sql-models.js        SQL persistence runtime
backend/ensure_schema.js     Chuẩn bị các bảng quan hệ
training/                     Dataset, checkpoint và công cụ train ngoại tuyến
start-full-backend.bat       Khởi động SQL-backed API trên Windows
```

Không commit `backend/.env`, mật khẩu SQL, JWT secret hoặc SMTP app password.
