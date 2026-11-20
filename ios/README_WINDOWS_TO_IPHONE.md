# Build & Cài đặt Outcome lên iPhone từ Windows (Không cần MacBook)

Vì bạn chỉ dùng **Windows + iPhone**, toàn bộ quy trình biên dịch Swift / Xcode chạy trên **GitHub Actions (`macos-26`)**:

## Bước 1: Đưa project lên GitHub & Chạy Cloud Build
1. Tạo repository GitHub (khuyên dùng **Public** hoặc Private có quota Actions macOS; repo Public chạy Actions miễn phí).
2. Push toàn bộ thư mục `Outcome/` (bao gồm `ios/` và `.github/workflows/ios-build.yml`) lên nhánh `main`.
3. Mở tab **Actions** trên GitHub → workflow **"iOS Cloud Build (No Mac Required)"** sẽ tự:
   - Chạy `swift test` kiểm tra toàn bộ `OutcomeCoreTests`.
   - Sinh `Outcome.xcodeproj` bằng `xcodegen generate`.
   - Build app và xuất file **`Outcome-unsigned.ipa`** ở mục **Artifacts**.

## Bước 2: Cài `.ipa` lên iPhone bằng Windows
Tải file `Outcome-unsigned.ipa` từ GitHub Actions Artifacts về máy Windows, sau đó cài qua một trong hai cách:
- **SideStore** hoặc **AltStore** (khuyên dùng, tự ký bằng Apple ID cá nhân, không cần tài khoản Dev 99$/năm; giới hạn tối đa 3 app sideload và gia hạn 7 ngày/lần qua Wi-Fi).
- **Sideloadly** trên Windows (cắm cáp Lightning/USB-C vào iPhone để cài trực tiếp `.ipa`).
- *(Nếu có Apple Developer Program 99$/năm)*: thêm certificate `.p12` + provisioning profile vào GitHub Secrets để xuất thẳng lên **TestFlight**.

## Bước 3: Thiết lập iOS Shortcuts Automation (Bắt noti MBBank / MoMo)
1. Mở app **Phím tắt (Shortcuts)** trên iPhone → tab **Tự động hóa (Automation)** → `+`.
2. Tạo Automation cho **Thông báo (Notification)** hoặc **App / Tin nhắn** (tùy phiên bản iOS hỗ trợ trigger notification của MBBank / MoMo; hoặc kết hợp Share Sheet / Quick Action nếu iOS giới hạn trigger notification trực tiếp của app ngân hàng).
3. Gọi Action của Outcome: **"Ghi nhận biến động số dư"** (`IngestNotificationIntent`), truyền vào:
   - `Ứng dụng nguồn`: `MBBank` hoặc `MoMo`
   - `Tiêu đề thông báo`
   - `Nội dung thông báo`
4. Chọn **Chạy ngay lập tức (Run Immediately)** để app tự chạy nền và bắn local notification nhắc chọn Tag.
