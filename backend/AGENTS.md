# Hướng dẫn cho backend

- Runtime hiện tại ở `server.js` và `sql-models.js`; `backend/data.json` không phải fallback runtime.
- SQL Server là nguồn có thẩm quyền. LM Studio chỉ xử lý tác vụ ngôn ngữ/vision; không để model tự bịa giá, thông số hoặc quyền truy cập.
- Không in hoặc commit `backend/.env`. Khi cần MCP SQL, dùng launcher dự án và cấu hình DBHub chỉ đọc.
- Không chạy `migrate-json-to-sql.js`, `migrate_from_json.js` hoặc `migrate_to_tables.js` lên DB runtime; chúng thuộc các mô hình dữ liệu khác nhau.
- Chỉ chạy `ensure_schema.js` khi người dùng yêu cầu chuẩn bị schema cho DB xác định. Không dùng script đó thay cho migration dữ liệu.
- Kiểm tra ownership/JWT, validation đầu vào, timeout và trạng thái LM Studio khi sửa route.

