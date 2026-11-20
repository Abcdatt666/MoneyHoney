# Outcome Design System — Tactile Bento (Apple HIG)

Tài liệu đặc tả thiết kế giao diện chính thức cho **Outcome** (đã duyệt phong cách **3. Tactile Bento**), tuân thủ tuyệt đối [AGENTS.md](./AGENTS.md) và các Apple HIG skills trong `.agents/skills/`.

---

## 1. Triết lý thị giác (Visual DNA)
- **Cảm hứng:** Apple Card / Apple Wallet kết hợp Apple Fitness.
- **Đặc trưng:** Bề mặt khối mềm (`cornerRadius: 20–22`, `.continuous`), độ tương phản bề mặt nhẹ nhàng (matte semantic surfaces), **không đổ bóng (no drop shadows)**, **không gradient phát sáng neon**.
- **Nguyên tắc phân lớp:**
  - **Content Layer:** Luôn đục (opaque semantic surface) để số tiền và chữ sắc nét tuyệt đối.
  - **Navigation Layer:** Thanh `TabView` nổi và nút `+` nổi dùng Liquid Glass tự nhiên của iOS 26+ (kèm fallback `.ultraThinMaterial` nếu hạ target).

---

## 2. Hệ thống màu sắc (Semantic Color Tokens)

Không hardcode mã hex trong SwiftUI View. Khai báo qua Apple Semantic Colors & `Assets.xcassets`:

| Token | Vai trò | Light Mode (tham chiếu) | Dark Mode (tham chiếu) |
|---|---|---|---|
| `systemGroupedBackground` | Nền màn hình chính | System Light Grouped | System Black Grouped |
| `secondarySystemGroupedBackground` | Nền Bento card / sheet form | System White | System Elevated Gray |
| `tertiarySystemGroupedBackground` | Nền chip chưa chọn / thanh track | System Light Gray | System Dark Gray |
| `AccentColor` | 1 màu nhấn duy nhất cho CTA & tab active | Warm Coral (`#FF6B2C`) | Warm Coral (`#FF7E47`) |
| `MBBankTileSurface` | Nền thẻ ví MBBank (matte nhẹ) | Cool Slate Tint (`blue` ~6% trên nền card) | Cool Slate Tint (`blue` ~12% trên nền card) |
| `MoMoTileSurface` | Nền thẻ ví MoMo (matte nhẹ) | Soft Rose Tint (`pink` ~6% trên nền card) | Soft Rose Tint (`pink` ~12% trên nền card) |
| `systemGreen` / `systemRed` / `systemOrange` | Thu nhập / Lệch số dư & Badge / Chờ duyệt | Apple Semantic | Apple Semantic |

---

## 3. Typography & Số học tài chính
- **Tiêu đề màn hình:** `NavigationStack` Large Title (`.largeTitle`, Bold).
- **Tổng số dư Hero:** `.font(.system(.largeTitle, design: .rounded).bold()).monospacedDigit()` (tự co giãn theo Dynamic Type).
- **Mọi số tiền VND & giờ giao dịch:** Bắt buộc gắn `.monospacedDigit()` để không nhảy hàng khi số thay đổi.
- **Định dạng tiền:** `13.450.000đ`, `-150.000đ`, `+120.000đ`.

---

## 4. Layout & Hình học (Bento & Tap Targets)
- **Horizontal Padding:** `16pt` chuẩn iOS.
- **Bento Card Radius:**
  - Card lớn (Chi tiêu tháng, Danh sách giao dịch, Nhắc đối soát): `22pt` (`.continuous`).
  - Dual-Wallet Tiles (MBBank / MoMo) & Tag Grid Chips: `20pt` / `16pt` (`.continuous`).
  - Primary Action Button ("Chốt số dư thực tế", "Lưu"): `Capsule` hoặc `16pt` continuous, chiều cao tối thiểu `50pt`.
- **Touch Target:** Mọi nút bấm, chip Tag, hàng giao dịch có vùng chạm tối thiểu `44x44pt`.

---

## 5. SF Symbols Mapping (Dữ liệu thật của Outcome)

| Thành phần | SF Symbol |
|---|---|
| Tab Tổng quan | `house.fill` |
| Tab Chờ duyệt | `tray.full.fill` |
| Tab Ví & Đối soát | `wallet.bifold.fill` (hoặc `creditcard.fill`) |
| Nút Thêm giao dịch tay | `plus` |
| MBBank | `building.columns.fill` |
| Ví MoMo | `wallet.pass.fill` |
| Chuyển nội bộ (`MOMO-CASHIN` / `CASHOUT`) | `arrow.left.arrow.right` |
| `tag_an_uong` (Ăn uống) | `fork.knife` |
| `tag_cf` (CF) | `cup.and.saucer.fill` |
| `tag_di_chuyen` (Di chuyển) | `car.fill` |
| `tag_mua_sam` (Mua sắm) | `bag.fill` |
| `tag_hoa_don` (Hóa đơn) | `doc.text.fill` |
| `tag_giai_tri` (Giải trí) | `sparkles` / `tv.fill` |
| `tag_tra_no` (Trả nợ) | `arrow.uturn.backward.circle.fill` |
| `tag_thu_nhap` (Thu nhập) | `arrow.down.left.circle.fill` |
| `tag_hoan_tien` (Hoàn tiền / Được trả) | `arrow.counterclockwise.circle.fill` |
| Nhắc đối soát cuối tháng | `bell.badge.fill` |

---

## 6. Kiến trúc 4 màn hình chính

1. **Tổng quan (`OverviewView`)**
   - Header: `"Tổng tài sản hiện có"` + số dư `.rounded.monospacedDigit()`, bên phải là pill badge `"N mới"` (nếu `pending_count > 0`, chạm để nhảy sang `Chờ duyệt`).
   - Dual-Wallet Bento Row (2 cột bằng nhau): `MBBankTile` + `MoMoTile`, chạm vào từng ô để lọc hoặc xem chi tiết ví.
   - Spending Allocation Bento Card: `"Chi tiêu tháng MM"` + tổng chi + thanh phân bổ Swift Charts bo tròn (`RoundedRectangle` stacked bar) + tối đa 3–4 pill % tag nổi bật nhất.
   - Latest Activity Bento Card: Danh sách giao dịch gần nhất (hiển thị badge trạng thái `Chờ gắn tag` hoặc `Nội bộ` rõ ràng).
2. **Chờ duyệt (`PendingInboxView`)**
   - Danh sách các `Transaction` có `status == .pending` dưới dạng Bento cards `22pt`, chạm vào **mở thẳng** `TagAssignmentSheet` (không lồng thêm màn hình push để giảm số lần chạm).
   - Nhóm tách biệt bên dưới cho giao dịch `INTERNAL_TRANSFER` (`MOMO-CASHIN` / `MOMO-CASHOUT`) ở trạng thái dịu (`opacity`), nhấn mạnh không tính vào chi tiêu tháng.
3. **Sheet gắn Tag & Nhập tay (`TagAssignmentSheet` / `ManualEntrySheet`)**
   - Native `.sheet` với `.presentationDetents([.medium, .large])` và `.presentationDragIndicator(.visible)`.
   - Header gồm nút đóng (`xmark`), tiêu đề giữa, nút `Lưu` dạng pill accent.
   - Summary card ở trên (ví, nội dung, số tiền lớn chính giữa).
   - Lưới Tag 3 cột (`LazyVGrid`, chiều cao mỗi ô `>= 46pt`, bo `16pt`) + nút `+ Tạo tag mới` inline.
   - Ô nhập `Ghi chú` bên dưới.
4. **Ví & Đối soát (`WalletsReconcileView`)**
   - Bento card hiển thị lịch nhắc kế tiếp (`12:00 trưa ngày làm việc cuối cùng của tháng`, tự lùi Thứ 6 nếu trùng Thứ 7/CN).
   - 2 ô ví cạnh nhau hiển thị số dư dự kiến, cho phép nhập số dư thực tế và tính ngay độ lệch (`Khớp 0đ` màu xanh lá / `Lệch -80.000đ` màu đỏ).
   - Nút CTA dạng Capsule: `"Chốt số dư thực tế"`.
