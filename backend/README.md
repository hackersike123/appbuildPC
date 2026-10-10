# PCBUILD LOCAL API

API tối giản, không cần framework hoặc database server. Dữ liệu MVP lưu trong
`data.json` để dễ chạy và dễ thay bằng PostgreSQL sau này.

## Chạy

```bash
cd backend
npm start
```

Mặc định chạy tại `http://localhost:3000`.

## Kết nối frontend

Web mặc định gọi `http://localhost:3000`. Android emulator gọi
`http://10.0.2.2:3000`. Với điện thoại Android thật, chạy backend trên cùng
mạng Wi-Fi rồi truyền IP máy tính:

```bash
flutter run -d <device> --dart-define=API_BASE_URL=http://192.168.1.10:3000
```

Thay `192.168.1.10` bằng IPv4 của máy chạy backend. Backend lắng nghe trên
mọi interface (`0.0.0.0`), nên cần cho phép Node.js qua Windows Firewall.

## API chính

```text
GET  /health
POST /api/v1/auth/register
POST /api/v1/auth/login
POST /api/v1/auth/forgot-password
GET  /api/v1/auth/me
GET  /api/v1/areas
POST /api/v1/location/resolve
GET  /api/v1/market/summary?areaId=hcm
GET  /api/v1/notifications
POST /api/v1/notifications/read
GET  /api/v1/products
GET  /api/v1/products/:id
GET  /api/v1/prices?productId=:id&areaId=hcm
POST /api/v1/builds
GET  /api/v1/builds
GET  /api/v1/builds/:id
DELETE /api/v1/builds/:id
PUT  /api/v1/builds/:id/components/:type
POST /api/v1/builds/:id/check
POST /api/v1/compatibility/check
POST /api/v1/scans
POST /api/v1/conversations
POST /api/v1/conversations/:id/messages
POST /api/v1/price-alerts
GET  /api/v1/price-alerts
```

Các endpoint cần tài khoản dùng header:

```text
Authorization: Bearer <accessToken>
```

Các giới hạn MVP hiện tại: token lưu trong bộ nhớ, mật khẩu dùng SHA-256,
catalog giá lưu trong JSON và scanner/chat chưa kết nối nhà cung cấp bên ngoài.
Khi đưa production cần PostgreSQL, Argon2/bcrypt, refresh token, rate limit,
HTTPS, validation schema và worker đồng bộ giá từ nhà cung cấp.
