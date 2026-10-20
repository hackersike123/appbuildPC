# PCBUILD LOCAL API

API Node.js native HTTP. Khi có đủ biến `MSSQL_*`, dữ liệu được lưu trong SQL
Server; nếu không có cấu hình SQL, test vẫn dùng file `data.json`.

## Chạy và kiểm thử

```powershell
cd backend
$env:JWT_SECRET="thay-bang-chuoi-bi-mat-dai"
npm start
```

Chạy test:

```powershell
cd backend
npm test
```

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
| `JWT_SECRET` | secret dev | Bắt buộc đổi khi public |
| `JWT_EXPIRES_IN` | `3600` | Thời hạn JWT, tính bằng giây |
| `PCBUILD_DB_FILE` | `backend/data.json` | File dữ liệu; dùng file tạm khi test |
| `MSSQL_SERVER` | - | Hostname SQL Server |
| `MSSQL_PORT` | - | Cổng SQL Server |
| `MSSQL_DATABASE` | - | Tên database |
| `MSSQL_USER` | - | Tài khoản SQL Server |
| `MSSQL_PASSWORD` | - | Mật khẩu, chỉ đặt trong `.env` |
| `MSSQL_ENCRYPT` | `false` | Bật TLS khi máy chủ yêu cầu |
| `MSSQL_TRUST_SERVER_CERTIFICATE` | `false` | Tin chứng chỉ tự ký |

### Kết nối SQL Server

Tạo `backend/.env` từ `.env.example`, sau đó đặt mật khẩu cục bộ. Không commit
file `.env`. API tự tạo bảng `dbo.pcbuild_app_state` khi khởi động và giữ
toàn bộ dữ liệu domain trong JSON payload để không thay đổi hợp đồng API trong
giai đoạn chuyển persistence. Script SQL tương ứng nằm tại
`backend/sql-schema.sql`.

Kiểm tra kết nối:

```powershell
cd backend
node --env-file=.env -e "const sql=require('mssql'); sql.connect({server:process.env.MSSQL_SERVER,port:Number(process.env.MSSQL_PORT),user:process.env.MSSQL_USER,password:process.env.MSSQL_PASSWORD,database:process.env.MSSQL_DATABASE,options:{encrypt:process.env.MSSQL_ENCRYPT==='true',trustServerCertificate:process.env.MSSQL_TRUST_SERVER_CERTIFICATE==='true'}}).then(async pool=>{console.log('SQL Server connected'); await pool.close()}).catch(error=>{console.error(error.message);process.exit(1)})"
```

Khởi động API:

```powershell
npm start
```

Nhập dữ liệu cũ từ `data.json` vào SQL Server theo chế độ merge:

```powershell
npm run migrate:json-to-sql
```

Lệnh này không xóa dữ liệu SQL Server và không ghi đè bản ghi đã có cùng
`id`. Sau khi nhập, API chỉ đọc/ghi trạng thái ứng dụng trong SQL Server khi
đủ cấu hình `MSSQL_*`; `data.json` chỉ còn là nguồn migration và fallback cho
test không bật SQL.

Không commit `JWT_SECRET` hoặc dữ liệu tài khoản thật.

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
