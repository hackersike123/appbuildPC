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
