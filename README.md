# PCBUILD LOCAL

Ứng dụng Flutter hỗ trợ xây dựng cấu hình PC theo khu vực, tham khảo giá linh
kiện, kiểm tra tương thích, quét linh kiện và tư vấn cấu hình. Web và Android
dùng chung REST API Node.js; tài khoản và build được phân quyền bằng JWT.

## Tính năng hiện có

- Luồng Chào mừng, đăng nhập, đăng ký và khôi phục mật khẩu.
- Xin quyền vị trí và camera thật trên Android; từ chối quyền vẫn không chặn demo.
- Xây cấu hình theo từng linh kiện: CPU, mainboard, GPU, RAM, SSD, PSU, case và
  tản nhiệt.
- Tự tính tổng giá, báo thiếu linh kiện và mở báo cáo tương thích.
- Danh sách build theo tài khoản, thông báo theo tài khoản, tư vấn BuildMate và giao diện khớp các frame Figma.
- Chạy trên Web và Android từ một codebase Flutter.

## Yêu cầu môi trường

- Flutter stable (Dart SDK theo `pubspec.yaml`).
- Android SDK cho Android build.
- Chrome hoặc Edge nếu chạy Web.

## Chạy dự án

```bash
flutter pub get
flutter analyze
flutter test
flutter run -d chrome
flutter run -d <android-device-id>
```

Build phát hành thử:

```bash
flutter build web
flutter build apk --debug
```

## Cấu trúc chính

```text
lib/main.dart                 # UI, navigation và demo state
test/widget_test.dart         # Widget/regression tests
assets/figma/                 # Asset local từ thiết kế
android/app/src/main/         # Android manifest và quyền thiết bị
.github/workflows/            # CI tự động trên GitHub Actions
backend/                      # API demo Node.js + JSON database
```

## Quyền thiết bị

Android khai báo camera và vị trí khi dùng ứng dụng. App gọi quyền hệ điều hành
thật qua `permission_handler`; nếu quyền bị từ chối, app dùng dữ liệu mẫu và
tiếp tục chạy để phục vụ demo.

## Giới hạn MVP

Backend, xác thực tài khoản, build theo tài khoản, khu vực và API giá MVP đã
được kết nối. Catalog giá hiện được lưu trong JSON và cập nhật theo dữ liệu
MVP; camera scanner, chatbot và đồng bộ giá từ nhà cung cấp bên ngoài vẫn là
các phần mở rộng tiếp theo.

## Quy trình đóng góp

1. Tạo branch từ `main`, ví dụ `feature/component-picker`.
2. Chạy `flutter analyze` và `flutter test`.
3. Cập nhật README/test khi thay đổi hành vi.
4. Tạo Pull Request vào `main`, mô tả thay đổi và kết quả kiểm thử.

Xem thêm [CONTRIBUTING.md](CONTRIBUTING.md).

## API và public demo

```bash
cd backend
npm start
```

Swagger UI: `http://localhost:3000/docs`. Hướng dẫn JWT, CRUD, VS Code Port
Forwarding và Gmail SMTP tại [backend/README.md](backend/README.md).

## Kết nối AI local bằng LM Studio và ngrok

Màn hình BuildMate gọi trực tiếp API OpenAI-compatible của LM Studio:

```text
POST <LM_STUDIO_URL>/chat/completions
```

Mục **Tài khoản > Kiểm tra kết nối LM Studio** có thể lấy danh sách model và
gửi một câu hỏi thử. Màn hình **Nhận diện linh kiện** cho phép chụp ảnh hoặc
chọn ảnh từ thư viện rồi gửi ảnh tới model Vision đang chạy.

Trong LM Studio, tải model, mở **Developer > Local Server**, chọn model rồi
bấm **Start Server**. Bật CORS nếu chạy Flutter Web. Kiểm tra:

```powershell
Invoke-RestMethod http://localhost:3105/v1/models
```

Chạy Flutter với LM Studio local:

```powershell
flutter run -d chrome --dart-define=API_BASE_URL=http://localhost:3000 --dart-define=LM_STUDIO_URL=http://localhost:3105/v1 --dart-define=LM_STUDIO_MODEL=qwen3-vl-8b-instruct
```

Với cấu hình public hiện tại, backend và LM Studio được giữ local, còn client
truy cập qua hai tunnel ngrok:

```powershell
flutter run -d chrome --dart-define=LM_STUDIO_URL=https://pillowlike-poikilitic-ciara.ngrok-free.dev/v1 --dart-define=LM_STUDIO_MODEL=qwen3-vl-8b-instruct
```

Android Emulator hoặc điện thoại thật dùng API public qua ngrok:

```powershell
flutter run -d <device-id> `
  --dart-define=API_BASE_URL=https://broiler-ocean-twistable.ngrok-free.dev `
  --dart-define=LM_STUDIO_URL=https://pillowlike-poikilitic-ciara.ngrok-free.dev/v1 `
  --dart-define=LM_STUDIO_MODEL=qwen3-vl-8b-instruct
```

Điện thoại thật hoặc máy ngoài mạng dùng ngrok:

```powershell
ngrok http 1234
flutter run -d <device-id> --dart-define=LM_STUDIO_URL=https://<ngrok-id>.ngrok-free.app/v1 --dart-define=LM_STUDIO_MODEL=qwen3-vl-8b-instruct
```

Không dùng `localhost` hoặc `127.0.0.1` trên điện thoại thật. URL ngrok chỉ
hoạt động khi LM Studio và ngrok vẫn đang chạy. Không public LM Studio lâu dài
vì URL này cho phép người có đường dẫn gọi model trên máy của bạn; nên giới
hạn truy cập ngrok hoặc chỉ dùng trong lúc demo.

Có thể truyền API key nếu server LM Studio/ngrok yêu cầu:

```powershell
flutter run -d chrome --dart-define=LM_STUDIO_URL=https://<ngrok-id>.ngrok-free.app/v1 --dart-define=LM_STUDIO_MODEL=qwen3-vl-8b-instruct --dart-define=LM_STUDIO_API_KEY=<key>
```

Các biến cấu hình được khai báo trong
`lib/config/ai_config.dart`: `LM_STUDIO_URL`, `LM_STUDIO_MODEL`,
`LM_STUDIO_API_KEY` và `LM_STUDIO_ENABLED`.

## Chạy local và public bằng ngrok

Backend và LM Studio chạy local trên cùng máy:

```powershell
# Terminal 1 - backend local
cd backend
npm start

# Terminal 2 - LM Studio local
# LM Studio Local Server: localhost:3105

# Terminal 3 - public backend
ngrok http 3000

# Terminal 4 - public LM Studio
ngrok http 3105
```

## Lệnh chạy Android qua API public

Thay `dc3b582c` bằng device ID hiển thị trong `flutter devices` nếu cần.

```powershell
flutter run -d dc3b582c `
  --dart-define=API_BASE_URL=https://broiler-ocean-twistable.ngrok-free.dev `
  --dart-define=LM_STUDIO_URL=https://pillowlike-poikilitic-ciara.ngrok-free.dev/v1 `
  --dart-define=LM_STUDIO_MODEL=qwen3-vl-8b-instruct
```

Lệnh trên dùng cả backend và LM Studio qua public API.

Lệnh trên dùng backend và LM Studio qua public API, không dùng địa chỉ LAN.
Hai tunnel ngrok và hai dịch vụ local phải đang chạy trước khi khởi động app.
