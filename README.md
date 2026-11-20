# Outcome — Core Logic (Giai đoạn 1)

Core Engine viết bằng **Python 3.12** (không phụ thuộc thư viện ngoài, thiết kế 1-to-1 để port sang Swift/SwiftData cho iOS 27).

## Cấu trúc thư mục

- `core/models.py`: Domain models (`WalletAccount`, `Tag`, `Transaction`, `BalanceReconciliation`, `RawNotification`, `NotificationPrompt`) và danh sách tag mặc định.
- `core/parser.py`: Bóc tách thông báo thực tế của `MBBank` (`TK ...|GD: +/-...VND dd/mm/yy HH:MM|SD: ...VND| ND: ... - Ma giao dich/ Trace ...`) và `MoMo`, tự nhận diện chuyển nội bộ `MOMO-CASHIN` / `MOMO-CASHOUT`, bỏ qua tin quảng cáo/OTP.
- `core/balance.py`: Cập nhật số dư 2 ví, đối soát cuối tháng và tính lịch nhắc **12:00 trưa ngày làm việc cuối cùng của tháng** (lùi về Thứ 6 nếu trùng Thứ 7/Chủ Nhật).
- `core/store.py`: Lưu trữ offline (`InMemoryStore` cho test và `JsonFileStore` cho lưu local).
- `core/engine.py`: `ExpenseEngine` gom toàn bộ luồng nghiệp vụ (bao gồm chống trùng lặp theo `trace_id`).
- `cli_demo.py`: Trình giả lập CLI trên Windows để test dán mẫu thông báo thật.

## Chạy bộ kiểm thử (Unit & E2E Tests)

```powershell
python -m unittest discover -s tests -v
```

## Chạy giả lập trên Windows

```powershell
python cli_demo.py
```
