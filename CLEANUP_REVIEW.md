# Rà soát, kiểm thử và dọn dự án

Ngày: 2026-10-23

## Đã xóa

- `build/` và `.dart_tool/`: đầu ra/cache Flutter; trước khi dọn `build/` chiếm khoảng 3,1 GB.
- `lib/ai_test_page.dart`: màn hình thử độc lập, không có import hay điều hướng đến `AITestPage`.
- `lib/test_harness.dart` và `.android-test/`: harness, AVD và ảnh tạm chỉ dùng để kiểm thử.
- `appbuildpc.iml`, `android/appbuildpc_android.iml`, `backend/server.log`.
- Script SQL dùng một lần/kiểm tra không được server hoặc npm gọi: `drop_all.js`, `drop_all2.js`, `check_alerts.js`, `check_schema.js`, `check_sql.js`, `check_sql_root.js`, `list_tables.js`, `list_all_tables.js`, `inspect_users.js`, `create_schema.js`, `create_schema_debug.js`, `test_alerts.js`.
- `PROJECT_SUMMARY.md`: bản tóm tắt cũ có thông tin PID/tunnel đã hết hạn và nhắc `start.bat` không tồn tại; hướng dẫn chính đã chuyển vào `README.md`.

## Đã giữ lại

- `backend/node_modules/`: backend cổng 3000 đang dùng các dependency này.
- `backend/ensure_schema.js`, `backend/migrate_to_tables.js`, `backend/migrate_from_json.js`: công cụ schema/migration có thể còn cần cho dữ liệu SQL.
- `backend/sql-store.js`, `backend/sql-schema.sql`, `backend/migrate-json-to-sql.js`: vẫn được package/docs cũ tham chiếu. Chúng dùng `pcbuild_app_state`, khác với các bảng quan hệ mà runtime gọi; cần thống nhất schema trước khi xóa hoặc chạy migration.
- `backend/data.json`, `backend/login.json`, `backend/.env`: có dữ liệu/tokens/cấu hình cục bộ. `backend/login.json` hiện đã được thêm vào `.gitignore`.
- `android/.gradle/` và Flutter `ephemeral` còn lại: giữ cache/config nền tảng để lần build tiếp theo không bị gián đoạn.

## Kiểm thử

- Flutter 3.47.2 / Dart 3.13.2: `flutter analyze` đạt; `flutter test` đạt 7 test; `flutter build web --release` và Android debug APK đều build thành công.
- Chrome release: trang chào, chọn khu vực và kiểm tra lỗi nhập đăng nhập hoạt động.
- Android Emulator API 35: kiểm tra chọn khu vực, form đăng nhập, catalog sản phẩm, lọc/tìm kiếm, so sánh, camera, thư viện ảnh và quét ảnh bằng LM Studio Vision.
- API hiện chạy ở cổng 3000 trả lời `/health`, `/api/v1/areas`, catalog và so sánh.
- `npm test` thất bại ở `backend/server.test.js:13`: test truy cập `db.users` nhưng runtime đặt `db = null` và dùng `sql-models.js`. Chưa có test backend cô lập phù hợp.
- Tìm kiếm GPU được thử trên backend tạm cổng 3001 sau khi sửa route `q`. Backend đang chạy cổng 3000 vẫn là tiến trình cũ; cần khởi động lại để nhận sửa lỗi tìm kiếm.

Các thao tác thành công cần tài khoản (đăng nhập thật, tạo/sửa/lưu build, hỗ trợ và chat có xác thực) không được gửi vào database đang dùng. Widget test vẫn kiểm tra màn hình/form và luồng giả lập.

## Ghi chú tài liệu

`README.md` đã bỏ liên kết tới `.github/workflows/ci.yml` và `start.bat` không có, thêm lệnh Android Emulator/LM Studio, và cảnh báo hai nhánh migration SQL khác schema.

Thư mục làm việc không có metadata `.git`, nên không thể xác định trạng thái track/untracked trước khi dọn.
