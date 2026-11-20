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

    def test_ignores_promotional_and_otp_notifications(self) -> None:
        promo = RawNotification(
            source_app=WalletId.MOMO,
            title="Ưu đãi cực sốc",
            body="Nhận ngay voucher giảm giá 50.000đ khi mua trà sữa hôm nay!",
            received_at=self.ts,
        )
        otp = RawNotification(
            source_app=WalletId.MBBANK,
            title="Mã OTP",
            body="Ma OTP cua quy khach la 482910. Khong chia se voi bat ky ai.",
            received_at=self.ts,
        )
        self.assertIsNone(parse_notification(promo))
        self.assertIsNone(parse_notification(otp))


if __name__ == "__main__":
    unittest.main()
