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

    def test_cross_app_linked_expense_mbbank_first_then_momo(self) -> None:
        engine = ExpenseEngine()
        t0 = datetime(2026, 11, 21, 11, 10, 0)
        engine.reconcile_balances(
            {WalletId.MBBANK: 3_000_000, WalletId.MOMO: 500_000}, now=t0
        )

        # MBBank fires first with raw gateway description
        r_mb = engine.ingest_notification(
            RawNotification(
                source_app=WalletId.MBBANK,
                title="Biến động số dư",
                body=(
                    "TK 0901234567|GD: -199,000VND 21/11/26 11:10|"
                    "SD: 2,801,000VND| ND: MOMO 2611219988 - Ma giao dich/ Trace 888999"
                ),
                received_at=t0 + timedelta(seconds=2),
            )
        )
        self.assertEqual(r_mb.status, "CREATED")

        # MoMo fires 4s later with clean merchant name ("Apple Services")
        r_momo = engine.ingest_notification(
            RawNotification(
                source_app=WalletId.MOMO,
                title="Thanh toán thành công",
                body="Bạn đã thanh toán thành công 199.000đ cho dịch vụ Apple Services.",
                received_at=t0 + timedelta(seconds=6),
            )
        )
        self.assertEqual(r_momo.status, "DUPLICATE")
        self.assertIsNone(r_momo.prompt)
        self.assertEqual(len(engine.store.list_transactions()), 1)
        self.assertEqual(engine.store.get_wallet(WalletId.MBBANK).balance, 2_801_000)
        self.assertEqual(engine.store.get_wallet(WalletId.MOMO).balance, 500_000)

        merged = engine.store.list_transactions()[0]
        self.assertEqual(merged.source_wallet_id, WalletId.MBBANK)
        self.assertEqual(merged.description, "Apple Services")
        self.assertEqual(merged.trace_id, "888999")

    def test_cross_app_linked_expense_momo_first_then_mbbank_rehomes_wallet(self) -> None:
        engine = ExpenseEngine()
        t0 = datetime(2026, 11, 21, 11, 12, 0)
        engine.reconcile_balances(
            {WalletId.MBBANK: 3_000_000, WalletId.MOMO: 500_000}, now=t0
        )

        # MoMo fires FIRST -> temporarily deducts from Ví MoMo
        r_momo = engine.ingest_notification(
            RawNotification(
                source_app=WalletId.MOMO,
                title="Thanh toán thành công",
                body="Bạn đã thanh toán thành công 75.000đ cho dịch vụ Grab.",
                received_at=t0 + timedelta(seconds=5),
            )
        )
        self.assertEqual(r_momo.status, "CREATED")
        assert r_momo.transaction is not None
        self.assertEqual(engine.store.get_wallet(WalletId.MOMO).balance, 425_000)

        # User immediately tags it before MBBank push even arrives
        engine.confirm_transaction(
            r_momo.transaction.id, tag_id="tag_di_chuyen", note="Đi làm sáng"
        )

        # MBBank fires 8s later -> refunds Ví MoMo, re-homes tx to MBBank, keeps tag & "Grab"
        r_mb = engine.ingest_notification(
            RawNotification(
                source_app=WalletId.MBBANK,
                title="Biến động số dư",
                body=(
                    "TK 0901234567|GD: -75,000VND 21/11/26 11:12|"
                    "SD: 2,925,000VND| ND: M_SERVICE 2611217766 - Ma giao dich/ Trace 444555"
                ),
                received_at=t0 + timedelta(seconds=13),
            )
        )
        self.assertEqual(r_mb.status, "DUPLICATE")
        self.assertEqual(len(engine.store.list_transactions()), 1)
        self.assertEqual(engine.store.get_wallet(WalletId.MOMO).balance, 500_000)
        self.assertEqual(engine.store.get_wallet(WalletId.MBBANK).balance, 2_925_000)

        rehomed = engine.store.list_transactions()[0]
        self.assertEqual(rehomed.source_wallet_id, WalletId.MBBANK)
        self.assertEqual(rehomed.description, "Grab")
        self.assertEqual(rehomed.tag_id, "tag_di_chuyen")
        self.assertEqual(rehomed.note, "Đi làm sáng")
        self.assertEqual(rehomed.status, TransactionStatus.CONFIRMED)
        self.assertEqual(rehomed.trace_id, "444555")

    def test_unrelated_same_amount_p2p_transfers_are_not_merged(self) -> None:
        engine = ExpenseEngine()
        t0 = datetime(2026, 11, 21, 12, 0, 0)
        engine.reconcile_balances(
            {WalletId.MBBANK: 1_000_000, WalletId.MOMO: 500_000}, now=t0
        )

        r_mb = engine.ingest_notification(
            RawNotification(
                source_app=WalletId.MBBANK,
                title="Biến động số dư",
                body=(
                    "TK 0901234567|GD: -50,000VND 21/11/26 12:00|"
                    "SD: 950,000VND| ND: NGUYEN VAN A chuyen tien - Ma giao dich/ Trace 111222"
                ),
                received_at=t0 + timedelta(seconds=2),
            )
        )
        r_momo = engine.ingest_notification(
            RawNotification(
                source_app=WalletId.MOMO,
                title="Chuyển tiền thành công",
                body="Bạn đã chuyển 50.000đ cho Lê Minh Khôi (0912345678).",
                received_at=t0 + timedelta(seconds=20),
            )
        )
        self.assertEqual(r_mb.status, "CREATED")
        self.assertEqual(r_momo.status, "CREATED")
        self.assertEqual(len(engine.store.list_transactions()), 2)
        self.assertEqual(engine.store.get_wallet(WalletId.MBBANK).balance, 950_000)
        self.assertEqual(engine.store.get_wallet(WalletId.MOMO).balance, 450_000)

    def test_internal_transfer_reverse_order_momo_before_mbbank_self_heals(self) -> None:
        engine = ExpenseEngine()
        t0 = datetime(2026, 11, 21, 13, 0, 0)
        engine.reconcile_balances(
            {WalletId.MBBANK: 2_000_000, WalletId.MOMO: 100_000}, now=t0
        )

        # MoMo notifies top-up first
        r_momo = engine.ingest_notification(
            RawNotification(
                source_app=WalletId.MOMO,
                title="Nạp tiền thành công",
                body="Bạn đã nạp 500.000đ từ MBBank vào Ví MoMo.",
                received_at=t0 + timedelta(seconds=3),
            )
        )
        self.assertEqual(r_momo.status, "CREATED")

        # MBBank notifies MOMO-CASHIN 5s later -> removes premature MoMo leg & records clean internal transfer
        r_mb = engine.ingest_notification(
            RawNotification(
                source_app=WalletId.MBBANK,
                title="Biến động số dư",
                body=(
                    "TK 0901234567|GD: -500,000VND 21/11/26 13:00|"
                    "SD: 1,500,000VND| ND: MOMO-CASHIN - Ma giao dich/ Trace 555666"
                ),
                received_at=t0 + timedelta(seconds=8),
            )
        )
        self.assertEqual(r_mb.status, "CREATED")
        self.assertEqual(len(engine.store.list_transactions()), 1)
        self.assertEqual(engine.store.get_wallet(WalletId.MBBANK).balance, 1_500_000)
        self.assertEqual(engine.store.get_wallet(WalletId.MOMO).balance, 600_000)


if __name__ == "__main__":
    unittest.main()
