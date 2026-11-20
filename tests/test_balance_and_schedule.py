import unittest
from datetime import datetime

from core.balance import (
    calculate_month_end_reminder,
    get_next_reconciliation_reminder,
)
from core.engine import ExpenseEngine
from core.models import RawNotification, WalletId


class TestBalanceAndSchedule(unittest.TestCase):
    def test_month_end_reminder_weekday(self) -> None:
        # 2026-11-30 is Monday -> stays 2026-11-30 12:00:00
        self.assertEqual(
            calculate_month_end_reminder(2026, 11),
            datetime(2026, 11, 30, 12, 0, 0),
        )

    def test_month_end_reminder_saturday_shifts_to_friday(self) -> None:
        # 2026-10-31 is Saturday -> shifts to Friday 2026-10-30 12:00:00
        self.assertEqual(
            calculate_month_end_reminder(2026, 10),
            datetime(2026, 10, 30, 12, 0, 0),
        )
        # 2026-02-28 is Saturday -> shifts to Friday 2026-02-27 12:00:00
        self.assertEqual(
            calculate_month_end_reminder(2026, 2),
            datetime(2026, 2, 27, 12, 0, 0),
        )

    def test_month_end_reminder_sunday_shifts_to_friday(self) -> None:
        # 2026-05-31 is Sunday -> shifts to Friday 2026-05-29 12:00:00
        self.assertEqual(
            calculate_month_end_reminder(2026, 5),
            datetime(2026, 5, 29, 12, 0, 0),
        )

    def test_leap_year_february(self) -> None:
        # 2024-02-29 is Thursday -> stays 2024-02-29 12:00:00
        self.assertEqual(
            calculate_month_end_reminder(2024, 2),
            datetime(2024, 2, 29, 12, 0, 0),
        )

    def test_next_reminder_rollover_including_year_boundary(self) -> None:
        self.assertEqual(
            get_next_reconciliation_reminder(datetime(2026, 11, 30, 11, 59, 0)),
            datetime(2026, 11, 30, 12, 0, 0),
        )
        self.assertEqual(
            get_next_reconciliation_reminder(datetime(2026, 11, 30, 12, 0, 0)),
            datetime(2026, 12, 31, 12, 0, 0),
        )
        self.assertEqual(
            get_next_reconciliation_reminder(datetime(2026, 12, 31, 12, 5, 0)),
            datetime(2027, 1, 29, 12, 0, 0),
        )

    def test_balances_with_internal_transfer_and_reconciliation_discrepancy(self) -> None:
        engine = ExpenseEngine()
        t0 = datetime(2026, 11, 1, 8, 0, 0)
        engine.reconcile_balances(
            {WalletId.MBBANK: 10_000_000, WalletId.MOMO: 500_000},
            note="Initial setup",
            now=t0,
        )

        # 1) MOMO-CASHIN 1,000,000 (MB -> MoMo)
        engine.ingest_notification(
            RawNotification(
                source_app=WalletId.MBBANK,
                title="Biến động số dư",
                body=(
                    "TK 0901234567|GD: -1,000,000VND 02/11/26 09:00|"
                    "SD: 9,000,000VND| ND: MOMO-CASHIN - Ma giao dich/ Trace 100001"
                ),
                received_at=datetime(2026, 11, 2, 9, 0, 5),
            )
        )
        # 2) Expense from MBBank 150,000
        r_exp = engine.ingest_notification(
            RawNotification(
                source_app=WalletId.MBBANK,
                title="Biến động số dư",
                body=(
                    "TK 0901234567|GD: -150,000VND 03/11/26 12:00|"
                    "SD: 8,850,000VND| ND: Thanh toan don hang - Ma giao dich/ Trace 100002"
                ),
                received_at=datetime(2026, 11, 3, 12, 0, 5),
            )
        )
        assert r_exp.transaction is not None
        engine.confirm_transaction(r_exp.transaction.id, tag_id="tag_an_uong")

        # 3) MOMO-CASHOUT 400,000 (MoMo -> MB)
        engine.ingest_notification(
            RawNotification(
                source_app=WalletId.MBBANK,
                title="Biến động số dư",
                body=(
                    "TK 0901234567|GD: +400,000VND 04/11/26 15:00|"
                    "SD: 9,250,000VND| ND: MOMO-CASHOUT - Ma giao dich/ Trace 100003"
                ),
                received_at=datetime(2026, 11, 4, 15, 0, 5),
            )
        )

        summary = engine.get_dashboard_summary(
            year=2026, month=11, now=datetime(2026, 11, 20, 15, 0, 0)
        )
        self.assertEqual(summary.mbbank_balance, 9_250_000)
        self.assertEqual(summary.momo_balance, 1_100_000)
        self.assertEqual(summary.total_balance, 10_350_000)
        self.assertEqual(summary.monthly_expense, 150_000)
        self.assertEqual(summary.monthly_income, 0)

        recs = engine.reconcile_balances(
            {WalletId.MBBANK: 9_250_000, WalletId.MOMO: 1_020_000},
            note="Chốt số dư cuối tháng 11",
            now=datetime(2026, 11, 30, 12, 0, 0),
        )
        momo_rec = next(r for r in recs if r.wallet_id == WalletId.MOMO)
        self.assertEqual(momo_rec.expected_balance, 1_100_000)
        self.assertEqual(momo_rec.actual_balance, 1_020_000)
        self.assertEqual(momo_rec.discrepancy, -80_000)


if __name__ == "__main__":
    unittest.main()
