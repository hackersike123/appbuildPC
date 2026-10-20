# PCBUILD LOCAL

PCBUILD LOCAL là ứng dụng Flutter cho Web và Android, giúp người dùng xây
dựng cấu hình PC theo khu vực, tham khảo giá linh kiện, kiểm tra tương thích,
lưu build theo tài khoản, quét linh kiện và hỏi trợ lý BuildMate AI.

## Kiến trúc hiện tại

```text
Flutter Web / Android
        |
        | REST + JWT
        v
Node.js API (backend/)
   |                |
   |                +--> LM Studio local hoặc tunnel ngrok
   |
   +--> SQL Server (runtime persistence)
```

- Flutter là client duy nhất cho Web và Android.
- Backend Node.js cung cấp REST API, xác thực JWT, build, sản phẩm, giá,
  thông báo, scanner, hỗ trợ và proxy AI.
- Khi có đủ biến `MSSQL_*`, backend đọc/ghi dữ liệu trong SQL Server.
- `data.json` chỉ là nguồn migration và fallback cho test không bật SQL.
- Flutter gọi `/api/v1/ai/chat`; backend gọi LM Studio server-side để tránh
  lỗi CORS và không lộ cấu hình AI trực tiếp trong trình duyệt.

## Tính năng

- Đăng ký, đăng nhập, JWT và khôi phục mật khẩu qua SMTP.
- Xác định khu vực bằng GPS và xin quyền camera trên Android.
- Chọn CPU, mainboard, GPU, RAM, SSD, PSU, case và tản nhiệt.
- Tính tổng giá, công suất, tiến độ build và kiểm tra tương thích.
- Lưu, mở, cập nhật, nhân bản và xóa build theo đúng tài khoản.
- Giá tham khảo theo khu vực, so sánh sản phẩm và theo dõi biến động giá.
- Quét linh kiện bằng camera/thư viện ảnh.
- Chat BuildMate AI và kiểm tra model LM Studio.
- Giao diện Flutter bám theo thiết kế Figma.

## Yêu cầu

- Flutter stable và Dart theo `pubspec.yaml`.
- Android SDK nếu chạy trên Android.
- Chrome hoặc Edge nếu chạy Web.
- Node.js hỗ trợ `--env-file` (Node 20+ khuyến nghị).
- SQL Server nếu chạy persistence production.
- LM Studio chỉ bắt buộc khi dùng chat hoặc scanner AI.

## Cài đặt

Tại thư mục repository:

```powershell
flutter pub get
```

Cài backend:

```powershell
cd backend
npm install
```

Tạo `backend/.env` từ [backend/.env.example](backend/.env.example), sau đó
điền các giá trị thật. Không commit `backend/.env`.

## Cấu hình backend

Các biến SQL Server runtime:

```env
PORT=3000
MSSQL_REQUIRED=true
MSSQL_SERVER=hackersike123.ddns.net
MSSQL_PORT=46494
MSSQL_DATABASE=PCBuildLocal
MSSQL_USER=tuan_dev
MSSQL_PASSWORD=<sql-password>
MSSQL_ENCRYPT=true
MSSQL_TRUST_SERVER_CERTIFICATE=true
MSSQL_CONNECTION_TIMEOUT=10000
MSSQL_REQUEST_TIMEOUT=10000
```

Các biến AI backend:

```env
LM_STUDIO_URL=http://localhost:3105/v1
LM_STUDIO_MODEL=qwen3-vl-8b-instruct
# LM_STUDIO_API_KEY=<optional>
```

`MSSQL_TRUST_SERVER_CERTIFICATE=true` phù hợp với chứng chỉ tự ký khi demo.
Production nên dùng chứng chỉ hợp lệ hoặc cấu hình mạng riêng an toàn hơn.

## Chạy backend

```powershell
cd backend
node --env-file=.env server.js
```

Hoặc:

```powershell
cd backend
npm start
```

Kiểm tra:

```powershell
Invoke-RestMethod http://localhost:3000/health
```

Kết quả mong đợi:

```json
{"ok":true,"service":"pcbuild-local-api"}
```

Swagger UI: <http://localhost:3000/docs>
OpenAPI JSON: <http://localhost:3000/openapi.json>

## Migration dữ liệu cũ

Migration merge dữ liệu từ `backend/data.json` vào SQL Server:

```powershell
cd backend
npm run migrate:json-to-sql
```

Script không xóa dữ liệu hiện có và giữ bản ghi SQL Server khi trùng `id`.
Backend tự tạo bảng `dbo.pcbuild_app_state` nếu bảng chưa tồn tại. Hiện trạng
dữ liệu được lưu trong một JSON payload để giữ nguyên hợp đồng API trong giai
đoạn chuyển đổi persistence.

## Chạy Flutter Web

### Local hoàn toàn

Nếu backend và LM Studio chạy trên cùng máy:

```powershell
flutter run -d chrome `
  --dart-define=API_BASE_URL=http://localhost:3000 `
  --dart-define=LM_STUDIO_MODEL=qwen3-vl-8b-instruct
```

Backend `.env` dùng:

```env
LM_STUDIO_URL=http://localhost:3105/v1
```

### Web qua backend ngrok

Khi backend được public bằng URL ngrok:

```powershell
flutter run -d chrome `
  --dart-define=API_BASE_URL=https://broiler-ocean-twistable.ngrok-free.dev `
  --dart-define=LM_STUDIO_MODEL=qwen3-vl-8b-instruct
```

Chrome chỉ gọi backend. Không cần truyền `LM_STUDIO_URL` cho Flutter vì backend
proxy request AI, tránh lỗi `Failed to fetch` do CORS.

## Chạy Android

Liệt kê thiết bị:

```powershell
flutter devices
```

Chạy thiết bị thật qua API public:

```powershell
flutter run -d dc3b582c `
  --dart-define=API_BASE_URL=https://broiler-ocean-twistable.ngrok-free.dev `
  --dart-define=LM_STUDIO_MODEL=qwen3-vl-8b-instruct
```

Thay `dc3b582c` bằng device ID thực tế. Không dùng `localhost` hoặc
`127.0.0.1` trên điện thoại thật; điện thoại cần truy cập được URL public.

## LM Studio và AI local

Trong LM Studio:

1. Mở **Developer > Local Server**.
2. Chọn model `qwen3-vl-8b-instruct`.
3. Bấm **Start Server**.
4. Kiểm tra server:

```powershell
Invoke-RestMethod http://localhost:3105/v1/models
```

Chat AI có thể mất lâu khi model đang tải hoặc chạy trên phần cứng hạn chế.
Client không đặt timeout cho request AI; các API thông thường vẫn có timeout
ngắn để phát hiện backend không phản hồi.

Nếu dùng tunnel:

```powershell
ngrok http 3000
ngrok http 3105
```

Đặt URL LM Studio tunnel trong `backend/.env`:

```env
LM_STUDIO_URL=https://<lm-studio-tunnel>/v1
```

Chỉ public tunnel trong thời gian demo và không đưa secret vào command hoặc
repository.

## Kiểm thử và build

Flutter:

```powershell
flutter analyze
flutter test
flutter build web
flutter build apk --debug
```

Backend:

```powershell
cd backend
npm test
node --check server.js
node --check sql-store.js
git diff --check
```

CI tại [.github/workflows/ci.yml](.github/workflows/ci.yml) chạy `flutter pub
get`, format, analyze, test và build Web.

## Cấu trúc chính

```text
lib/main.dart                 # UI và navigation Flutter
lib/api_client.dart           # REST client, JWT và AI proxy call
lib/config/ai_config.dart     # compile-time AI flags
lib/services/                 # camera, GPS, scanner và LM Studio helpers
test/widget_test.dart         # Flutter widget tests
assets/figma/                 # assets từ thiết kế
android/app/src/main/         # Android manifest và quyền thiết bị
backend/server.js             # Node.js REST API
backend/sql-store.js          # SQL Server persistence
backend/migrate-json-to-sql.js # migration JSON sang SQL
backend/sql-schema.sql        # schema bootstrap
backend/data.json             # seed/fallback/migration source
```

## Bảo mật và vận hành

- Không commit `backend/.env`, mật khẩu SQL, JWT secret hoặc SMTP app password.
- Dùng JWT cho các endpoint theo tài khoản.
- Không public SQL Server trực tiếp nếu không cần; giới hạn firewall hoặc dùng
  VPN.
- Hạn chế thời gian sống của tunnel ngrok và tắt tunnel sau khi demo.
- Nếu credential từng bị lộ, phải rotate credential trước khi public lại.

## Quy trình đóng góp

1. Tạo branch từ branch hiện tại hoặc `main`.
2. Chạy `flutter analyze`, `flutter test` và test backend liên quan.
3. Cập nhật README khi thay đổi lệnh chạy, API hoặc cấu hình.
4. Tạo Pull Request với mô tả thay đổi và kết quả kiểm thử.

Xem thêm [CONTRIBUTING.md](CONTRIBUTING.md) và
[backend/README.md](backend/README.md).
