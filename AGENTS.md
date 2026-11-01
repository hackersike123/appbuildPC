# Hướng dẫn cho agent

## Kiến trúc

- Client Flutter trong `lib/` chỉ gọi REST API Node.js; không kết nối trực tiếp tới SQL Server hoặc model AI.
- Backend runtime dùng SQL Server qua `backend/sql-models.js`. SQL là nguồn có thẩm quyền cho catalog, giá, build, tương thích và dữ liệu tài khoản.
- Backend dùng LM Studio cho chat, nhận diện ảnh và AI Build dự phòng. Adapter và checkpoint trong `training/` không được nạp vào runtime hiện tại.
- Đọc `README.md` và hướng dẫn `AGENTS.md` gần thư mục đang sửa trước khi thay đổi kiến trúc.

## Quy tắc dự án

- Giữ ranh giới Flutter → REST API → SQL Server/LM Studio; không thêm truy cập DB hoặc model trực tiếp từ client.
- Không đưa mật khẩu, token, chuỗi kết nối hoặc dữ liệu người dùng vào Git, log, prompt hay ví dụ. `backend/.env` là cấu hình cục bộ.
- Không chạy migration dữ liệu hoặc script chuẩn bị schema trên SQL Server từ xa nếu người dùng chưa yêu cầu rõ. Các script `backend/migrate-json-to-sql.js`, `backend/migrate_from_json.js` và `backend/migrate_to_tables.js` thuộc các mô hình cũ; không dùng chúng cho runtime hiện tại.
- Dùng DBHub MCP chỉ để dò schema và truy vấn đọc. Không dùng kết quả từ model làm nguồn dữ liệu thay cho SQL.
- Chỉ sửa dữ liệu huấn luyện/checkpoint khi nhiệm vụ yêu cầu rõ; không coi ảnh minh họa hay dữ liệu tài khoản là tập train.
- Dùng các lệnh Flutter/backend được ghi trong README khi người dùng yêu cầu kiểm tra. Không chạy train hoặc migration như một bước kiểm tra thông thường.

## Lệnh kiểm tra có sẵn

- Flutter: `flutter analyze`, `flutter test`
- Backend: `cd backend; npm test`, `node --check backend/server.js`
- Build Web: `flutter build web`

