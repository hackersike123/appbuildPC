# Hướng dẫn cho Flutter client

- Mọi dữ liệu catalog, giá, tương thích, tài khoản và build phải đi qua REST API trong backend.
- Tôn trọng `API_BASE_URL` và các URL riêng cho Web, Android Emulator, điện thoại LAN; không hardcode `localhost` cho thiết bị thật.
- Kiểm tra khác biệt quyền camera, thư viện ảnh và vị trí giữa Web và Android trước khi sửa luồng scan.
- Không đưa SQL credentials, LM Studio key hoặc logic quyết định nghiệp vụ có thẩm quyền vào client.
- Giữ nhãn phân biệt giá thị trường với giá catalog ước tính; không tự tạo dữ liệu lịch sử giá.

