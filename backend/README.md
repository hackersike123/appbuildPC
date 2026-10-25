# PCBUILD LOCAL API

API Node.js native HTTP. Runtime hiện tại truy cập SQL Server qua
`sql-models.js` và cần các bảng quan hệ được tạo bởi `ensure_schema.js`.
`data.json` không còn là fallback runtime.

## Khởi động backend đầy đủ trên Windows

Từ thư mục gốc, chạy [start-full-backend.bat](../start-full-backend.bat):

```powershell
.\start-full-backend.bat
```

Launcher kiểm tra file `.env`, dependencies và SQL Server từ xa, rồi mở Node API
ở cổng `3000`. Model LM Studio cần được nạp sẵn qua Local Server theo cấu hình
`LM_STUDIO_URL`; launcher không khởi động model tự huấn luyện.

Để chạy thủ công:

```powershell
cd backend
npm start
```

Xác nhận dịch vụ:

```powershell
Invoke-RestMethod http://localhost:3000/health
```

API docs ở `http://localhost:3000/docs`; OpenAPI JSON ở
`http://localhost:3000/openapi.json`. Dừng API bằng `Ctrl+C` trong cửa sổ
console. SQL Server runtime là máy chủ từ xa.

## Kiểm thử

```powershell
cd backend
npm test
```

`npm test` chạy smoke test `/health`, OpenAPI và xác thực chặn debug headers
bằng cổng ngẫu nhiên; test không ghi vào SQL database.

Swagger UI mở tại `http://localhost:3000/docs`. OpenAPI JSON ở
`http://localhost:3000/openapi.json`.

## JWT thật

Login:

```http
POST /api/v1/auth/login
Content-Type: application/json

{"email":"user@example.com","password":"password123"}
```

Response có JWT dạng `header.payload.signature`:

```json
{
  "accessToken": "...",
  "tokenType": "Bearer",
  "expiresIn": 3600
}
```

Gọi API cần đăng nhập bằng:

```http
Authorization: Bearer <accessToken>
```

Biến môi trường:

| Biến | Mặc định | Ý nghĩa |
|---|---:|---|
| `PORT` | `3000` | Cổng HTTP |
| `JWT_SECRET` | — | Bắt buộc cấu hình một secret riêng trước khi chạy |
| `JWT_EXPIRES_IN` | `3600` | Thời hạn JWT, tính bằng giây |
| `MSSQL_SERVER` | - | Hostname SQL Server |
| `MSSQL_PORT` | - | Cổng SQL Server |
| `MSSQL_DATABASE` | - | Tên database |
| `MSSQL_USER` | - | Tài khoản SQL Server |
| `MSSQL_PASSWORD` | - | Mật khẩu, chỉ đặt trong `.env` |
| `MSSQL_ENCRYPT` | `false` | Bật TLS khi máy chủ yêu cầu |
| `MSSQL_TRUST_SERVER_CERTIFICATE` | `false` | Tin chứng chỉ tự ký |
| `LM_STUDIO_URL` | - | OpenAI-compatible endpoint của LM Studio |
| `LM_STUDIO_MODEL` | `qwen3-vl-8b-instruct` | Model LM Studio dùng cho chat/build |
| `LM_STUDIO_VISION_MODEL` | `LM_STUDIO_MODEL` | Model LM Studio dùng cho nhận diện ảnh |
| `LM_STUDIO_API_KEY` | - | Bearer token nếu Local Server bật xác thực |
| `LM_STUDIO_TIMEOUT_MS` | `240000` | Timeout cho mỗi lượt gọi model |

Chat, tư vấn, scan ảnh, OCR, rà SKU và AI Build fallback đều chỉ gọi LM Studio.
Mỗi tác vụ nhận system prompt chuyên PCBUILD; dữ liệu động về giá, linh kiện,
lịch sử và build chỉ lấy từ SQL. Adapter tự train không được nạp hoặc gọi khi
chạy ứng dụng; giữ nguyên tập dữ liệu và checkpoint để train sau này.

Luồng scan dùng LM Studio đọc ảnh/OCR, sau đó LM Studio xác nhận với danh sách
ứng viên SQL rút gọn và ảnh gốc. Không gửi toàn bộ catalog 13.834 sản phẩm vào
prompt vision. Chỉ lưu
SKU khi ID cuối cùng khớp catalog SQL, confidence >= 0,9 và nội dung không mơ hồ.
Ảnh quá lớn được báo lỗi 413/422 rõ ràng thay vì lỗi parse chung.

Chat nhận catalog, build hiện tại và ví dụ hướng dẫn PC lưu trong
`dbo.ai_pc_examples`; build được ghép từ SQL trước, LM Studio chỉ tạo phương án
dự phòng khi SQL không có cấu hình hợp lệ. Với câu hỏi nguồn của build đã lưu, backend trả tóm
tắt theo `powerAssessment` SQL để giữ đúng khoảng dư/thiếu; không lấy `marginW`
thay cho margin hãng. Route scan chỉ nhận ID trong catalog khi confidence >=
0,9 và nội dung không báo mơ hồ, kể cả khi LM Studio là provider cuối cùng.

Model vision LM Studio đọc ảnh và xác nhận SKU với catalog. Pipeline detector
YOLO và adapter train được giữ ngoại tuyến; app không nạp chúng.

Ví dụ cấu hình hai model local trong `backend/.env`:

```env
LM_STUDIO_URL=http://127.0.0.1:3106/v1
LM_STUDIO_MODEL=qwen3-vl-8b-instruct
LM_STUDIO_VISION_MODEL=qwen3-vl-8b-instruct
LM_STUDIO_TIMEOUT_MS=240000
```

LM Studio phải chạy Local Server và nạp model đúng tên tại `LM_STUDIO_URL`.
Nếu LM Studio ngừng hoạt động, các tác vụ AI sẽ báo provider unavailable.
LM Studio hỗ trợ cấu hình mức GPU offload qua CLI
(`lms load --gpu off`) và qua thiết lập model.

Catalog SQL có thêm `recommendedPsuW` và `recommendedPsuSource` cho GPU. Bộ
kiểm tra PSU lấy mức lớn nhất giữa khuyến nghị của đúng model GPU, tải CPU/GPU
trong catalog nhân 1,3 cộng 100W dự phòng, và mức sàn 450W. API trả riêng tải
ước tính, mức đề nghị, PSU đang chọn, watt dư/thiếu và nguồn dữ liệu hãng.

### Kết nối SQL Server

Tạo `backend/.env` từ `.env.example`, sau đó đặt mật khẩu cục bộ. Không commit
file `.env`. Server hiện dùng các bảng quan hệ mà `ensure_schema.js` tạo. Chạy
script từ thư mục gốc dự án để nó đọc đúng `backend/.env`:

```powershell
node backend/ensure_schema.js
```

Khi khởi động, API tự thêm `dbo.market_history` và các cột lưu ảnh/phân tích
cho `dbo.scans`; không cần lưu dữ liệu nghiệp vụ trong file trên máy.

`sql-store.js`, `sql-schema.sql` và `migrate-json-to-sql.js` vẫn thuộc nhánh
persistence cũ dùng một bảng `dbo.pcbuild_app_state`; nhánh này không khớp với
`sql-models.js` mà runtime hiện gọi. Không chạy migration đó trước khi thống
nhất lại mô hình dữ liệu.

Kiểm tra kết nối:

```powershell
cd backend
node --env-file=.env -e "const sql=require('mssql'); sql.connect({server:process.env.MSSQL_SERVER,port:Number(process.env.MSSQL_PORT),user:process.env.MSSQL_USER,password:process.env.MSSQL_PASSWORD,database:process.env.MSSQL_DATABASE,options:{encrypt:process.env.MSSQL_ENCRYPT==='true',trustServerCertificate:process.env.MSSQL_TRUST_SERVER_CERTIFICATE==='true'}}).then(async pool=>{console.log('SQL Server connected'); await pool.close()}).catch(error=>{console.error(error.message);process.exit(1)})"
```

Khởi động API:

```powershell
npm start
```

Các script migration hiện có thuộc hai mô hình dữ liệu khác nhau. Trước khi
chạy script nào, hãy đối chiếu `migrate-json-to-sql.js` (bảng đơn
`pcbuild_app_state`) với `migrate_to_tables.js` (các bảng quan hệ runtime) và
sao lưu database. Chưa có một lệnh migration duy nhất được xác nhận cho runtime
hiện tại.

Không commit `JWT_SECRET` hoặc dữ liệu tài khoản thật.

## Nguồn giá catalog

`dbo.products.price` là giá catalog cơ sở. Khi khu vực chưa có bản ghi giá
`dbo.market`, API trả `priceSource=catalog_estimate`; app gắn nhãn giá ước tính.
Giá này có thể dùng cho tổng build tham khảo, nhưng không tạo dữ liệu biến động,
lịch sử hay cảnh báo thị trường. Các chức năng theo dõi giá chỉ dùng bản ghi có
giá dương trong `dbo.market`. Khi có giá thật, cập nhật `dbo.market` theo
`productId` và `areaId`; schema không cần đổi.

## CRUD build để chấm bằng Swagger/Postman

Các endpoint bảo vệ bằng JWT:

```text
POST   /api/v1/builds
GET    /api/v1/builds
GET    /api/v1/builds/:id
PUT    /api/v1/builds/:id
PUT    /api/v1/builds/:id/components/:type
DELETE /api/v1/builds/:id
```

`PUT /api/v1/builds/:id` cập nhật tên, ngân sách hoặc khu vực. Endpoint
component cập nhật đúng sản phẩm trong build và trả về build mới nhất để app
không bị lệch state. Catalog seed có nhiều lựa chọn cho CPU, mainboard, GPU,
RAM, SSD, PSU và case; dữ liệu cũ sẽ được bổ sung các sản phẩm còn thiếu khi
backend khởi động.

Trong Swagger UI, bấm **Authorize**, nhập `Bearer <accessToken>`, rồi chạy
theo thứ tự register/login, POST, GET, PUT và DELETE. Backend kiểm tra
`userId`, nên tài khoản này không thể đọc hoặc xóa build của tài khoản khác.

## Public API bằng VS Code Port Forwarding

Backend phải bind `0.0.0.0`; server đã cấu hình sẵn điều này. Thực hiện:

1. Chạy backend trên máy:
   ```powershell
   cd backend
   $env:JWT_SECRET="chuoi-bi-mat-dai-khac"
   npm start
   ```
2. Trong VS Code mở **Ports** → **Forward a Port** → nhập `3000`.
3. Đặt Visibility là **Public** nếu muốn thiết bị ngoài máy truy cập.
4. Sao chép HTTPS Forwarded Address, ví dụ `https://abc-3000.app.github.dev`.
5. Kiểm tra `https://abc-3000.app.github.dev/health` và `/docs`.
6. Chạy Flutter với cùng URL:
   ```powershell
   flutter run -d chrome --dart-define=API_BASE_URL=https://abc-3000.app.github.dev
   flutter run -d <android-device> --dart-define=API_BASE_URL=https://abc-3000.app.github.dev
   ```

Không dùng `localhost` hoặc `10.0.2.2` khi app Android truy cập port public.

## Gmail SMTP và quên mật khẩu

Backend đã dùng Nodemailer để gửi email Gmail thật. Cài dependencies:

```powershell
cd backend
npm install
```

Thiết lập Gmail:

1. Bật xác minh 2 bước cho tài khoản Gmail.
2. Vào Google Account → **Security** → **2-Step Verification** →
   **App passwords**.
3. Tạo App Password mới, chọn tên `PCBUILD LOCAL`.
4. Sao chép mật khẩu 16 ký tự. Đây là mật khẩu SMTP, không phải mật khẩu
   Gmail thông thường.
5. Tạo file `backend/.env` (không commit file này) với:

```env
SMTP_HOST=smtp.gmail.com
SMTP_PORT=465
SMTP_SECURE=true
SMTP_USER=your-address@gmail.com
SMTP_PASS=xxxx xxxx xxxx xxxx
APP_BASE_URL=https://abc-3000.app.github.dev
```

`APP_BASE_URL` là URL mà người dùng có thể mở để đặt lại mật khẩu. Backend
hiện đã có sẵn trang `/reset-password`; vì vậy có thể dùng trực tiếp URL API
public (ví dụ URL ngrok/VS Code Port Forwarding). Nếu có URL Flutter Web
public riêng, đặt URL đó để sử dụng giao diện Flutter; trong cả hai trường
hợp, `API_BASE_URL` của Flutter phải trỏ về URL API.

Khởi động backend bằng Node có hỗ trợ `.env`:

```powershell
node --env-file=.env server.js
```

Hoặc dùng `npm start` sau khi đã khai báo biến môi trường trong PowerShell.

Kiểm tra kết nối SMTP:

```powershell
node --env-file=.env -e "const nodemailer=require('nodemailer'); const t=nodemailer.createTransport({host:process.env.SMTP_HOST,port:Number(process.env.SMTP_PORT),secure:process.env.SMTP_SECURE==='true',auth:{user:process.env.SMTP_USER,pass:process.env.SMTP_PASS}}); t.verify().then(()=>console.log('SMTP OK')).catch(err=>{console.error(err);process.exit(1)})"
```

Nếu dùng Gmail Workspace có chính sách chặn App Password, dùng OAuth2
hoặc SMTP relay của quản trị viên thay vì tắt bảo mật tài khoản.

Luồng đã triển khai:

```text
POST /api/v1/auth/forgot-password
  -> tạo token ngẫu nhiên, chỉ lưu hash token và expiresAt
  -> gửi link APP_BASE_URL/reset-password?token=...
POST /api/v1/auth/reset-password
  -> kiểm tra hash + hạn dùng + dùng một lần
  -> hash mật khẩu mới và cập nhật user
```

Gọi API:

```http
POST /api/v1/auth/forgot-password
Content-Type: application/json

{"email":"your-email@gmail.com"}
```

Sau khi nhận email, gửi token và mật khẩu mới:

```http
POST /api/v1/auth/reset-password
Content-Type: application/json

{"token":"token-trong-link-email","password":"matkhau-moi-8-ky-tu"}
```

Token chỉ có hiệu lực 15 phút và bị xóa sau khi sử dụng. Nếu SMTP lỗi với
tài khoản tồn tại, API trả `503 SMTP_UNAVAILABLE` và token tạm thời bị xóa để
người dùng có thể yêu cầu lại.

Không gửi mật khẩu qua email, không lưu reset token dạng rõ trong database,
không đưa `SMTP_PASS` lên GitHub. Khi test, dùng hộp thư riêng và xóa App
Password nếu không tiếp tục sử dụng.
