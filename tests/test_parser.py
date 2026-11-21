import unittest
from datetime import datetime

from core.models import Direction, RawNotification, TransactionType, WalletId
from core.parser import parse_notification


class TestParser(unittest.TestCase):
    def setUp(self) -> None:
        self.ts = datetime(2026, 11, 20, 15, 55, 0)

    def test_real_mbbank_incoming_format(self) -> None:
        raw = RawNotification(
            source_app=WalletId.MBBANK,
            title="Biến động số dư",
            body=(
                "TK 0901234567|GD: +500,000VND 20/11/26 15:45|"
                "SD: 12,500,000VND| ND: NGUYEN VAN A chuyen tien - Ma giao dich/ Trace 123456"
            ),
            received_at=self.ts,
        )
        parsed = parse_notification(raw)
        self.assertIsNotNone(parsed)
        assert parsed is not None
        self.assertEqual(parsed.tx_type, TransactionType.INCOME)
        self.assertEqual(parsed.direction, Direction.IN)
        self.assertEqual(parsed.amount, 500000)
        self.assertEqual(parsed.reported_balance_after, 12500000)
        self.assertEqual(parsed.trace_id, "123456")
        self.assertEqual(parsed.description, "NGUYEN VAN A chuyen tien")
        self.assertEqual(parsed.occurred_at, datetime(2026, 11, 20, 15, 45))

    def test_real_mbbank_outgoing_format(self) -> None:
        raw = RawNotification(
            source_app=WalletId.MBBANK,
            title="Biến động số dư",
            body=(
                "TK 0901234567|GD: -150,000VND 20/11/26 15:50|"
                "SD: 12,350,000VND| ND: Thanh toan don hang - Ma giao dich/ Trace 654321"
            ),
            received_at=self.ts,
        )
        parsed = parse_notification(raw)
        assert parsed is not None
        self.assertEqual(parsed.tx_type, TransactionType.EXPENSE)
        self.assertEqual(parsed.direction, Direction.OUT)
        self.assertEqual(parsed.amount, 150000)
        self.assertEqual(parsed.reported_balance_after, 12350000)
        self.assertEqual(parsed.trace_id, "654321")
        self.assertEqual(parsed.description, "Thanh toan don hang")
        self.assertEqual(parsed.occurred_at, datetime(2026, 11, 20, 15, 50))

    def test_mbbank_momo_cashin_internal_transfer(self) -> None:
        raw = RawNotification(
            source_app=WalletId.MBBANK,
            title="Biến động số dư",
            body=(
                "TK 0901234567|GD: -500,000VND 20/11/26 16:00|"
                "SD: 11,850,000VND| ND: MOMO-CASHIN 0901234567 - Ma giao dich/ Trace 777888"
            ),
            received_at=self.ts,
        )
        parsed = parse_notification(raw)
        assert parsed is not None
        self.assertEqual(parsed.tx_type, TransactionType.INTERNAL_TRANSFER)
        self.assertEqual(parsed.source_wallet_id, WalletId.MBBANK)
        self.assertEqual(parsed.target_wallet_id, WalletId.MOMO)
        self.assertEqual(parsed.amount, 500000)
        self.assertEqual(parsed.trace_id, "777888")

    def test_mbbank_momo_cashout_internal_transfer(self) -> None:
        raw = RawNotification(
            source_app=WalletId.MBBANK,
            title="Biến động số dư",
            body=(
                "TK 0901234567|GD: +300,000VND 20/11/26 16:10|"
                "SD: 12,150,000VND| ND: MOMO-CASHOUT - Ma giao dich/ Trace 999000"
            ),
            received_at=self.ts,
        )
        parsed = parse_notification(raw)
        assert parsed is not None
        self.assertEqual(parsed.tx_type, TransactionType.INTERNAL_TRANSFER)
        self.assertEqual(parsed.source_wallet_id, WalletId.MOMO)
        self.assertEqual(parsed.target_wallet_id, WalletId.MBBANK)
        self.assertEqual(parsed.amount, 300000)
        self.assertEqual(parsed.trace_id, "999000")

    def test_momo_receive_money_without_plus_sign(self) -> None:
        raw = RawNotification(
            source_app=WalletId.MOMO,
            title="Nhận tiền thành công",
            body="Trần Minh Quân đã chuyển cho bạn 120.000đ. Lời nhắn: Tiền cafe sáng",
            received_at=self.ts,
        )
        parsed = parse_notification(raw)
        assert parsed is not None
        self.assertEqual(parsed.tx_type, TransactionType.INCOME)
        self.assertEqual(parsed.direction, Direction.IN)
        self.assertEqual(parsed.amount, 120000)
        self.assertEqual(parsed.description, "Trần Minh Quân - Tiền cafe sáng")

    def test_momo_all_real_popup_formats(self) -> None:
        # 1) Nhận tiền từ ví MoMo (kèm SĐT và lời nhắn ngoặc kép)
        r1 = parse_notification(
            RawNotification(
                source_app=WalletId.MOMO,
                title="Bạn vừa nhận được tiền",
                body='Bạn vừa nhận được 120.000đ từ Nguyễn Văn A (0901234567). Lời nhắn: "Tiền ăn trưa"',
                received_at=self.ts,
            )
        )
        assert r1 is not None
        self.assertEqual(r1.tx_type, TransactionType.INCOME)
        self.assertEqual(r1.amount, 120000)
        self.assertEqual(r1.description, "Nguyễn Văn A - Tiền ăn trưa")

        # 2) Nhận tiền từ Ngân hàng qua VietQR
        r2 = parse_notification(
            RawNotification(
                source_app=WalletId.MOMO,
                title="Nhận tiền thành công",
                body="Bạn vừa nhận được 500.000đ từ NGUYEN VAN B qua VietQR/Chuyển tiền nhanh.",
                received_at=self.ts,
            )
        )
        assert r2 is not None
        self.assertEqual(r2.tx_type, TransactionType.INCOME)
        self.assertEqual(r2.amount, 500000)
        self.assertEqual(r2.description, "NGUYEN VAN B")

        # 3) Trừ tiền tự động (Liên kết Apple Services / Grab)
        r3 = parse_notification(
            RawNotification(
                source_app=WalletId.MOMO,
                title="Thanh toán thành công",
                body="Bạn đã thanh toán thành công 199.000đ cho dịch vụ Apple Services.",
                received_at=self.ts,
            )
        )
        assert r3 is not None
        self.assertEqual(r3.tx_type, TransactionType.EXPENSE)
        self.assertEqual(r3.direction, Direction.OUT)
        self.assertEqual(r3.amount, 199000)
        self.assertEqual(r3.description, "Apple Services")

        # 4) Hoàn tiền (kể cả khi Shortcuts không truyền Title)
        r4 = parse_notification(
            RawNotification(
                source_app=WalletId.MOMO,
                title="",
                body="Bạn vừa được hoàn 50.000đ từ giao dịch Shopee vào Ví MoMo.",
                received_at=self.ts,
            )
        )
        assert r4 is not None
        self.assertEqual(r4.tx_type, TransactionType.INCOME)
        self.assertEqual(r4.direction, Direction.IN)
        self.assertEqual(r4.amount, 50000)
        self.assertEqual(r4.description, "Hoàn tiền - Shopee")

        # 5) Tiền lời Túi Thần Tài -> bỏ qua (cộng vào Túi Thần Tài, không vào Ví MoMo chính)
        r5 = parse_notification(
            RawNotification(
                source_app=WalletId.MOMO,
                title="Tiền lời Túi Thần Tài",
                body="Chúc mừng bạn nhận được 1.250đ tiền lời hôm nay từ Túi Thần Tài.",
                received_at=self.ts,
            )
        )
        self.assertIsNone(r5)

        # 5b) Rút tiền từ Túi Thần Tài về Ví MoMo -> THU vào Ví MoMo
        r5b = parse_notification(
            RawNotification(
                source_app=WalletId.MOMO,
                title="Túi Thần Tài",
                body="Giao dịch rút 500.000đ từ Túi Thần Tài về Ví MoMo thành công.",
                received_at=self.ts,
            )
        )
        assert r5b is not None
        self.assertEqual(r5b.tx_type, TransactionType.INCOME)
        self.assertEqual(r5b.direction, Direction.IN)
        self.assertEqual(r5b.amount, 500000)
        self.assertEqual(r5b.description, "Rút Túi Thần Tài")

        # 5c) Nạp / Tự động tích lũy từ Ví MoMo vào Túi Thần Tài -> CHI khỏi Ví MoMo
        r5c = parse_notification(
            RawNotification(
                source_app=WalletId.MOMO,
                title="Túi Thần Tài",
                body="[Túi Thần Tài] Hệ thống đã tự động tích lũy 300.000đ từ Ví MoMo của bạn.",
                received_at=self.ts,
            )
        )
        assert r5c is not None
        self.assertEqual(r5c.tx_type, TransactionType.EXPENSE)
        self.assertEqual(r5c.direction, Direction.OUT)
        self.assertEqual(r5c.amount, 300000)
        self.assertEqual(r5c.description, "Nạp Túi Thần Tài")

        # 6) Chuyển tiền đi từ MoMo (kể cả khi Lời nhắn chứa chữ "hoàn tiền")
        r6 = parse_notification(
            RawNotification(
                source_app=WalletId.MOMO,
                title="Chuyển tiền thành công",
                body='Bạn đã chuyển 85.000đ cho Lê Minh Khôi (0912345678). Lời nhắn: "Hoàn tiền cafe"',
                received_at=self.ts,
            )
        )
        assert r6 is not None
        self.assertEqual(r6.tx_type, TransactionType.EXPENSE)
        self.assertEqual(r6.amount, 85000)
        self.assertEqual(r6.description, "Chuyển Lê Minh Khôi")

        # 7) Quét QR / Thanh toán tại cửa hàng
        r7 = parse_notification(
            RawNotification(
                source_app=WalletId.MOMO,
                title="Thanh toán thành công",
                body="Thanh toán thành công 45.000đ tại Highlands Coffee.",
                received_at=self.ts,
            )
        )
        assert r7 is not None
        self.assertEqual(r7.tx_type, TransactionType.EXPENSE)
        self.assertEqual(r7.amount, 45000)
        self.assertEqual(r7.description, "Highlands Coffee")

        # 8) Nạp điện thoại (phải là CHI, không nhầm với nạp ví)
        r8 = parse_notification(
            RawNotification(
                source_app=WalletId.MOMO,
                title="Nạp tiền điện thoại thành công",
                body="Bạn đã nạp tiền điện thoại 50.000đ cho thuê bao 0901234567.",
                received_at=self.ts,
            )
        )
        assert r8 is not None
        self.assertEqual(r8.tx_type, TransactionType.EXPENSE)
        self.assertEqual(r8.direction, Direction.OUT)
        self.assertEqual(r8.amount, 50000)

        # 9) Nhận tiền có Lời nhắn chứa từ khóa promo ("voucher") vẫn không bị bỏ sót
        r9 = parse_notification(
            RawNotification(
                source_app=WalletId.MOMO,
                title="Bạn vừa nhận được tiền",
                body='Bạn vừa nhận được 70.000đ từ Phạm Anh (0988111222). Lời nhắn: "Chia tiền voucher"',
                received_at=self.ts,
            )
        )
        assert r9 is not None
        self.assertEqual(r9.tx_type, TransactionType.INCOME)
        self.assertEqual(r9.amount, 70000)
        self.assertEqual(r9.description, "Phạm Anh - Chia tiền voucher")

    def test_ignores_promotional_and_otp_notifications(self) -> None:
        promo = RawNotification(
            source_app=WalletId.MOMO,
            title="Ưu đãi cực sốc",
            body="Nhận ngay voucher giảm giá 50.000đ khi mua trà sữa hôm nay!",
            received_at=self.ts,
        )
        gift_card_promo = RawNotification(
            source_app=WalletId.MOMO,
            title="Quà tặng dành riêng cho bạn",
            body="Chúc mừng bạn nhận được thẻ quà 50.000đ thanh toán hóa đơn!",
            received_at=self.ts,
        )
        otp = RawNotification(
            source_app=WalletId.MBBANK,
            title="Mã OTP",
            body="Ma OTP cua quy khach la 482910. Khong chia se voi bat ky ai.",
            received_at=self.ts,
        )
        self.assertIsNone(parse_notification(promo))
        self.assertIsNone(parse_notification(gift_card_promo))
        self.assertIsNone(parse_notification(otp))

    def test_hardened_bank_and_momo_edge_cases(self) -> None:
        # #1) MBBank credit card statement reminder, credit card spend, savings book -> ignored
        cc_statement = RawNotification(
            source_app=WalletId.MBBANK,
            title="Thông báo sao kê",
            body="Thong bao sao ke the tin dung thang 11/2026. Tong du no: VND 5,200,000. Vui long thanh toan truoc ngay 25-11-2026.",
            received_at=self.ts,
        )
        cc_spend = RawNotification(
            source_app=WalletId.MBBANK,
            title="Biến động thẻ",
            body="The tin dung VISA 4084xxxxxx phat sinh giao dich chi tieu VND 1,500,000 tai THE COFFEE HOUSE. So du kha dung: VND 18,500,000.",
            received_at=self.ts,
        )
        savings = RawNotification(
            source_app=WalletId.MBBANK,
            title="Tiết kiệm số",
            body="Quy khach da mo thanh cong So tiet kiem so 0123xxxxxx so tien 50,000,000 VND.",
            received_at=self.ts,
        )
        self.assertIsNone(parse_notification(cc_statement))
        self.assertIsNone(parse_notification(cc_spend))
        self.assertIsNone(parse_notification(savings))

        # #2) MoMo Ví Trả Sau debt reminder & postpaid payment -> ignored
        vts_reminder = RawNotification(
            source_app=WalletId.MOMO,
            title="Nhắc thanh toán Ví Trả Sau",
            body="Toàn bộ dư nợ Ví Trả Sau của bạn là 1.850.000đ. Vui lòng thanh toán trước ngày 05/12.",
            received_at=self.ts,
        )
        vts_payment = RawNotification(
            source_app=WalletId.MOMO,
            title="Thanh toán thành công",
            body="Thanh toán thành công 150.000đ cho Shopee bằng nguồn Ví Trả Sau.",
            received_at=self.ts,
        )
        self.assertIsNone(parse_notification(vts_reminder))
        self.assertIsNone(parse_notification(vts_payment))

        # #4) MBBank MOMO_CASHIN (underscore variant) -> internal transfer
        cashin_underscore = parse_notification(
            RawNotification(
                source_app=WalletId.MBBANK,
                title="Biến động số dư",
                body="TK 0901234567|GD: -200,000VND 21/11/26 10:00|SD: 5,000,000VND| ND: MOMO_CASHIN 0901234567",
                received_at=self.ts,
            )
        )
        assert cashin_underscore is not None
        self.assertEqual(cashin_underscore.tx_type, TransactionType.INTERNAL_TRANSFER)
        self.assertEqual(cashin_underscore.amount, 200000)

        # #5 & #6) MBBank prefix currency (VND 99,000) & "So du kha dung:" stripped properly
        fee_tx = parse_notification(
            RawNotification(
                source_app=WalletId.MBBANK,
                title="Thông báo thu phí",
                body="Giao dich tru phi thuong nien the 9704xxxxxx so tien VND 99,000. So du kha dung: VND 1,450,000.",
                received_at=self.ts,
            )
        )
        assert fee_tx is not None
        self.assertEqual(fee_tx.tx_type, TransactionType.EXPENSE)
        self.assertEqual(fee_tx.amount, 99000)
        self.assertEqual(fee_tx.reported_balance_after, 1450000)

        # #8) Decimal .00 tail does not multiply by 100x
        dec_tx = parse_notification(
            RawNotification(
                source_app=WalletId.MBBANK,
                title="Biến động số dư",
                body="TK 0901234567|GD: -150,000.00VND 21/11/26 10:15|SD: 4,850,000.00VND| ND: Thanh toan",
                received_at=self.ts,
            )
        )
        assert dec_tx is not None
        self.assertEqual(dec_tx.amount, 150000)
        self.assertEqual(dec_tx.reported_balance_after, 4850000)


if __name__ == "__main__":
    unittest.main()
