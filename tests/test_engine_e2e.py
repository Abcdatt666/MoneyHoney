import tempfile
import unittest
from datetime import datetime, timedelta
from pathlib import Path

from core.engine import ExpenseEngine
from core.models import Direction, RawNotification, TransactionStatus, WalletId
from core.store import JsonFileStore


class TestEngineEndToEnd(unittest.TestCase):
    def test_full_offline_json_roundtrip_and_trace_dedup(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            db_path = Path(tmp) / "outcome_data.json"
            engine = ExpenseEngine(store=JsonFileStore(db_path))

            engine.reconcile_balances(
                {WalletId.MBBANK: 5_000_000, WalletId.MOMO: 200_000},
                now=datetime(2026, 11, 1, 9, 0, 0),
            )

            # Custom tag creation + duplicate protection
            custom_tag = engine.add_custom_tag("Thú cưng")
            with self.assertRaises(ValueError):
                engine.add_custom_tag("  thú cưng ")

            # 1) User receives MBBank notification and ignores it -> stays PENDING
            t1 = datetime(2026, 11, 20, 15, 50, 2)
            res1 = engine.ingest_notification(
                RawNotification(
                    source_app=WalletId.MBBANK,
                    title="Biến động số dư",
                    body=(
                        "TK 0901234567|GD: -150,000VND 20/11/26 15:50|"
                        "SD: 4,850,000VND| ND: Thanh toan don hang - Ma giao dich/ Trace 654321"
                    ),
                    received_at=t1,
                )
            )
            self.assertEqual(res1.status, "CREATED")
            assert res1.prompt is not None
            self.assertTrue(res1.prompt.should_prompt)
            self.assertEqual(res1.prompt.title, "MBBank -150.000đ")
            self.assertEqual(len(engine.list_pending_transactions()), 1)

            # 2) Same Trace ID delivered again is rejected as DUPLICATE
            dup = engine.ingest_notification(
                RawNotification(
                    source_app=WalletId.MBBANK,
                    title="Biến động số dư",
                    body=(
                        "TK 0901234567|GD: -150,000VND 20/11/26 15:50|"
                        "SD: 4,850,000VND| ND: Thanh toan don hang - Ma giao dich/ Trace 654321"
                    ),
                    received_at=t1 + timedelta(minutes=2),
                )
            )
            self.assertEqual(dup.status, "DUPLICATE")

            # 3) Confirm pending transaction with tag & note
            assert res1.transaction is not None
            engine.confirm_transaction(
                res1.transaction.id, tag_id="tag_mua_sam", note="Mua đồ Shopee"
            )
            self.assertEqual(len(engine.list_pending_transactions()), 0)

            # 4) Manual MoMo wallet spend using custom tag
            manual_tx = engine.add_manual_transaction(
                wallet_id=WalletId.MOMO,
                direction=Direction.OUT,
                amount=90_000,
                tag_id=custom_tag.id,
                description="Pet Mart",
                note="Mua cát mèo bằng ví MoMo",
                occurred_at=datetime(2026, 11, 20, 16, 0, 0),
            )
            self.assertEqual(manual_tx.status, TransactionStatus.CONFIRMED)

            # Reload from disk into a fresh ExpenseEngine instance to verify persistence
            reloaded = ExpenseEngine(store=JsonFileStore(db_path))
            summary = reloaded.get_dashboard_summary(
                year=2026, month=11, now=datetime(2026, 11, 20, 16, 5, 0)
            )
            self.assertEqual(summary.mbbank_balance, 4_850_000)
            self.assertEqual(summary.momo_balance, 110_000)
            self.assertEqual(summary.total_balance, 4_960_000)
            self.assertEqual(summary.monthly_expense, 240_000)
            self.assertEqual(summary.expense_by_tag["Mua sắm"], 150_000)
            self.assertEqual(summary.expense_by_tag["Thú cưng"], 90_000)

            # Delete manual tx -> balance reverts cleanly
            self.assertTrue(reloaded.delete_transaction(manual_tx.id))
            self.assertEqual(
                reloaded.store.get_wallet(WalletId.MOMO).balance, 200_000
            )

    def test_cross_app_duplicate_guard_on_internal_transfer(self) -> None:
        engine = ExpenseEngine()
        t0 = datetime(2026, 11, 20, 11, 0, 0)
        engine.reconcile_balances(
            {WalletId.MBBANK: 2_000_000, WalletId.MOMO: 100_000}, now=t0
        )

        r_mb = engine.ingest_notification(
            RawNotification(
                source_app=WalletId.MBBANK,
                title="Biến động số dư",
                body=(
                    "TK 0901234567|GD: -500,000VND 20/11/26 11:00|"
                    "SD: 1,500,000VND| ND: MOMO-CASHIN - Ma giao dich/ Trace 333444"
                ),
                received_at=t0 + timedelta(seconds=10),
            )
        )
        self.assertEqual(r_mb.status, "CREATED")
        assert r_mb.prompt is not None
        self.assertFalse(r_mb.prompt.should_prompt)

        r_momo = engine.ingest_notification(
            RawNotification(
                source_app=WalletId.MOMO,
                title="MoMo",
                body="Nạp tiền vào ví +500.000đ từ MBBank",
                received_at=t0 + timedelta(seconds=25),
            )
        )
        self.assertEqual(r_momo.status, "DUPLICATE")
        self.assertEqual(engine.store.get_wallet(WalletId.MOMO).balance, 600_000)
        self.assertEqual(engine.store.get_wallet(WalletId.MBBANK).balance, 1_500_000)


if __name__ == "__main__":
    unittest.main()
