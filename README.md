# Kiểm kho – quét mã vạch & so sánh tồn lý thuyết

App Flutter (Android). Nhập file tồn lý thuyết từ Excel/CSV → quét mã vạch kiểm đếm → báo cáo chênh lệch → xuất Excel.

## Lấy APK
1. Tạo repo GitHub, push toàn bộ thư mục này lên nhánh `main`.
2. Vào tab **Actions → Build APK** (tự chạy khi push; hoặc bấm *Run workflow*).
3. Khi xong, mở run → mục **Artifacts** → tải `kiem-kho-apk` → giải nén lấy `app-release.apk`.
4. (Tùy chọn) đẩy tag `v1.0` để APK tự đính vào mục **Releases**.

Cài APK lên điện thoại: bật "Cài đặt từ nguồn không xác định".

## File tồn đầu vào
Nhận `.xlsx` hoặc `.csv`. App tự dò dòng tiêu đề (có "Mã vật tư" + "Số lượng") ở mọi sheet, các cột:
`Mã vật tư | Tên vật tư | ĐVT | Số lượng | Giá trị | (Giá BQ - tùy chọn)`.
Dòng "Tổng cộng" bị bỏ qua; mã trùng được cộng dồn.

## Công thức
- **Giá BQ** = Giá trị tồn ÷ Số lượng tồn (`calcAvgPrice` trong `lib/models.dart`; tồn = 0 thì dùng cột Giá BQ trong file nếu có).
- **Giá trị đã kiểm** = SL kiểm × Giá BQ
- **Chênh lệch** = SL kiểm − SL tồn; giá trị chênh = chênh SL × Giá BQ
- Mã chưa quét lần nào tính là "Chưa kiểm" (không phải "Thiếu"), nhưng vẫn được tính vào chênh lệch toàn kho.

## Khớp mã vạch
So khớp sau khi bỏ ký tự đặc biệt/viết hoa. Nếu mã vạch dài hơn mã vật tư (có tiền tố/hậu tố) vẫn nhận nếu chứa mã vật tư (≥ 8 ký tự). Mã không có trong danh sách được ghi vào "Hàng ngoài danh sách".
