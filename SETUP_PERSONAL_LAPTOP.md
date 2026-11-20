# Ghi chú chuyển sang Laptop cá nhân

Tài liệu này lưu lại toàn bộ yêu cầu cài đặt skills và quy tắc thiết kế để tiếp tục dự án **Outcome** khi bạn chuyển thư mục này sang máy cá nhân (không cài trên máy công ty).

---

## 1. Quy tắc thiết kế đã lưu sẵn trong dự án

* Quy tắc **iOS Native Design Rules (Strict Apple HIG Compliance)** đã được lưu tại [AGENTS.md](./AGENTS.md) ở thư mục gốc của dự án.

---

## 2. Danh sách Skills cần cài trên Laptop cá nhân

Khi chuyển thư mục `Outcome/` sang máy cá nhân, cài đặt các skill sau vào thư mục `.agents/skills/` của dự án (hoặc global `~/.gemini/config/skills/`):

1. **`anthropics/skills`** (lấy skill `frontend-design`):
   * Repo: `https://github.com/anthropics/skills` (thư mục `skills/frontend-design`)
2. **`pbakaus/impeccable`**:
   * Repo: `https://github.com/pbakaus/impeccable`
3. **`AvdLee/SwiftUI-Agent-Skill`**:
   * Repo: `https://github.com/AvdLee/SwiftUI-Agent-Skill`
4. **`twostraws/SwiftUI-Agent-Skill`**:
   * Repo: `https://github.com/twostraws/SwiftUI-Agent-Skill`
5. **`raintree-technology/apple-hig-skills`** (tên chuẩn trên GitHub của `apple-hig-skills`):
   * Repo: `https://github.com/raintree-technology/apple-hig-skills`
6. **`sickn33/antigravity-awesome-skills`**:
   * Repo: `https://github.com/sickn33/antigravity-awesome-skills` *(Lưu ý: repo này rất lớn với hàng nghìn skills; khi cài chỉ nên copy/chọn lọc các skills liên quan đến iOS / SwiftUI / Frontend Design vào `.agents/skills/` để tránh làm nặng context).*

### Gợi ý lệnh cài nhanh trên máy cá nhân (Git + Sparse/Shallow)

```bash
# Chạy trong thư mục tạm ngoài project rồi copy các thư mục SKILL.md cần dùng vào Outcome/.agents/skills/
git clone --depth 1 https://github.com/anthropics/skills.git
git clone --depth 1 https://github.com/pbakaus/impeccable.git
git clone --depth 1 https://github.com/AvdLee/SwiftUI-Agent-Skill.git
git clone --depth 1 https://github.com/twostraws/SwiftUI-Agent-Skill.git
git clone --depth 1 https://github.com/raintree-technology/apple-hig-skills.git
git clone --depth 1 https://github.com/sickn33/antigravity-awesome-skills.git
```

*Nguyên tắc sử dụng đã chốt:* Mỗi lần bắt đầu thiết kế hoặc dựng màn hình UI mới, luôn đọc và áp dụng các skills liên quan trong `.agents/skills/` cùng với [AGENTS.md](./AGENTS.md).
