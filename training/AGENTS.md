# Hướng dẫn cho training ngoại tuyến

- Adapter QLoRA, checkpoint, eval và detector trong thư mục này không được app/backend hiện tại nạp.
- Không train hoặc ghi đè thư mục `training/output/` trừ khi người dùng yêu cầu cụ thể.
- Không dùng hội thoại, ảnh scan hoặc dữ liệu tài khoản thật làm dữ liệu train.
- Giữ riêng train/validation/test; không gộp held-out test vào quá trình tune.
- Chỉ đề xuất đưa model vào runtime sau khi qua đầy đủ đánh giá hành vi và hồi quy được mô tả trong README.

