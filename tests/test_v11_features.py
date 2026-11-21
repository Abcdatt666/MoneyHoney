import unittest
from datetime import datetime, timedelta

from core.engine import ExpenseEngine
from core.models import Direction, RawNotification, TransactionStatus, WalletId


class TestV11Features(unittest.TestCase):
    def test_tag_suggester_cold_start_and_personal_learning(self) -> None:
        engine = ExpenseEngine()
        t0 = datetime(2026, 11, 21, 9, 0, 0)

        # Cold-start: Highlands Coffee -> tag_cf first
        r1 = engine.ingest_notification(
            RawNotification(
                source_app=WalletId.MOMO,
                title="Thanh toán thành công",
                body="Thanh toán thành công 55.000đ tại Highlands Coffee.",
                received_at=t0,
            )
        )
        assert r1.transaction is not None
        cold_suggestions = engine.suggest_tags(r1.transaction, limit=3)
        self.assertEqual(len(cold_suggestions), 3)
        self.assertEqual(cold_suggestions[0].id, "tag_cf")

        # Cold-start: Apple Services -> tag_hoa_don first
        r_apple = engine.ingest_notification(
            RawNotification(
                source_app=WalletId.MOMO,
                title="Thanh toán thành công",
                body="Bạn đã thanh toán thành công 199.000đ cho dịch vụ Apple Services.",
                received_at=t0 + timedelta(minutes=5),
            )
        )
        assert r_apple.transaction is not None
        self.assertEqual(engine.suggest_tags(r_apple.transaction, limit=3)[0].id, "tag_hoa_don")

        # Personal learning: teach custom tag "Thú cưng" for "Pet Mart"
        pet_tag = engine.add_custom_tag("Thú cưng", now=t0)
        engine.add_manual_transaction(
            wallet_id=WalletId.MOMO,
            direction=Direction.OUT,
            amount=120_000,
            tag_id=pet_tag.id,
            description="Pet Mart Quận 1",
            occurred_at=t0 + timedelta(minutes=10),
        )

        r_pet = engine.ingest_notification(
            RawNotification(
                source_app=WalletId.MOMO,
                title="Thanh toán thành công",
                body="Thanh toán thành công 85.000đ tại Pet Mart Quận 1.",
                received_at=t0 + timedelta(hours=1),
            )
        )
        assert r_pet.transaction is not None
        learned_suggestions = engine.suggest_tags(r_pet.transaction, limit=3)
        self.assertEqual(learned_suggestions[0].id, pet_tag.id)

        # Refund notification -> tag_hoan_tien first
        r_refund = engine.ingest_notification(
            RawNotification(
                source_app=WalletId.MOMO,
                title="Hoàn tiền thành công",
                body="Bạn vừa được hoàn 50.000đ từ giao dịch Shopee vào Ví MoMo.",
                received_at=t0 + timedelta(hours=2),
            )
        )
        assert r_refund.transaction is not None
        self.assertEqual(engine.suggest_tags(r_refund.transaction, limit=3)[0].id, "tag_hoan_tien")

    def test_full_transaction_edit_recalculates_balances_cleanly(self) -> None:
        engine = ExpenseEngine()
        t0 = datetime(2026, 11, 21, 10, 0, 0)
        engine.reconcile_balances(
            {WalletId.MBBANK: 2_000_000, WalletId.MOMO: 500_000}, now=t0
        )

        tx = engine.add_manual_transaction(
            wallet_id=WalletId.MOMO,
            direction=Direction.OUT,
            amount=100_000,
            tag_id="tag_an_uong",
            description="Cơm trưa",
            occurred_at=t0,
        )
        self.assertEqual(engine.store.get_wallet(WalletId.MOMO).balance, 400_000)
        self.assertEqual(engine.store.get_wallet(WalletId.MBBANK).balance, 2_000_000)

        # Edit: switch wallet MoMo -> MBBank, change amount 100k -> 250k, update tag & note
        updated = engine.update_transaction(
            tx_id=tx.id,
            wallet_id=WalletId.MBBANK,
            direction=Direction.OUT,
            amount=250_000,
            tag_id="tag_mua_sam",
            description="Mua giày thể thao",
            note="Đặt online",
            occurred_at=t0 + timedelta(minutes=30),
        )
        self.assertEqual(updated.source_wallet_id, WalletId.MBBANK)
        self.assertEqual(updated.amount, 250_000)
        self.assertEqual(updated.tag_id, "tag_mua_sam")
        self.assertEqual(updated.status, TransactionStatus.CONFIRMED)
        self.assertEqual(engine.store.get_wallet(WalletId.MOMO).balance, 500_000)
        self.assertEqual(engine.store.get_wallet(WalletId.MBBANK).balance, 1_750_000)

    def test_convert_momo_cashin_internal_transfer_into_wifi_bill_expense(self) -> None:
        engine = ExpenseEngine()
        t0 = datetime(2026, 11, 21, 11, 30, 0)
        engine.reconcile_balances(
            {WalletId.MBBANK: 3_000_000, WalletId.MOMO: 200_000}, now=t0
        )

        # MBBank reports MOMO-CASHIN when paying WiFi bill on MoMo via linked MBBank
        r_mb = engine.ingest_notification(
            RawNotification(
                source_app=WalletId.MBBANK,
                title="Biến động số dư",
                body=(
                    "TK 0901234567|GD: -220,000VND 21/11/26 11:30|"
                    "SD: 2,780,000VND| ND: MOMO-CASHIN - Ma giao dich/ Trace 900111"
                ),
                received_at=t0,
            )
        )
        assert r_mb.transaction is not None
        # Initially logged as internal transfer (+220k on MoMo, -220k on MBBank)
        self.assertEqual(engine.store.get_wallet(WalletId.MBBANK).balance, 2_780_000)
        self.assertEqual(engine.store.get_wallet(WalletId.MOMO).balance, 420_000)

        # User taps internal transfer and tags it as "Hóa đơn" (WiFi)
        converted = engine.update_transaction(
            tx_id=r_mb.transaction.id,
            wallet_id=WalletId.MBBANK,
            direction=Direction.OUT,
            amount=220_000,
            tag_id="tag_hoa_don",
            description="Bill WiFi FPT",
            note="Tháng 11",
            occurred_at=t0,
        )
        self.assertEqual(converted.target_wallet_id, None)
        self.assertEqual(converted.tag_id, "tag_hoa_don")
        # MoMo ghost balance is reverted cleanly back to 200k; MBBank stays 2,780k
        self.assertEqual(engine.store.get_wallet(WalletId.MOMO).balance, 200_000)
        self.assertEqual(engine.store.get_wallet(WalletId.MBBANK).balance, 2_780_000)
        summary = engine.get_dashboard_summary(year=2026, month=11, now=t0)
        self.assertEqual(summary.monthly_expense, 220_000)
        self.assertEqual(summary.expense_by_tag["Hóa đơn"], 220_000)

    def test_momo_cashin_plus_momo_bill_payment_auto_converts_both_orders(self) -> None:
        # Order 1: MBBank MOMO-CASHIN arrives first, MoMo payment arrives 4s later
        e1 = ExpenseEngine()
        t0 = datetime(2026, 11, 21, 14, 0, 0)
        e1.reconcile_balances({WalletId.MBBANK: 2_000_000, WalletId.MOMO: 100_000}, now=t0)
        e1.ingest_notification(
            RawNotification(
                source_app=WalletId.MBBANK,
                title="Biến động số dư",
                body=(
                    "TK 0901234567|GD: -220,000VND 21/11/26 14:00|"
                    "SD: 1,780,000VND| ND: MOMO-CASHIN - Ma giao dich/ Trace 900222"
                ),
                received_at=t0 + timedelta(seconds=1),
            )
        )
        r_momo = e1.ingest_notification(
            RawNotification(
                source_app=WalletId.MOMO,
                title="Thanh toán thành công",
                body="Bạn đã thanh toán thành công 220.000đ cho dịch vụ FPT Telecom.",
                received_at=t0 + timedelta(seconds=5),
            )
        )
        self.assertEqual(r_momo.status, "CREATED")
        assert r_momo.prompt is not None and r_momo.prompt.should_prompt
        self.assertEqual(len(e1.store.list_transactions()), 1)
        self.assertEqual(e1.store.get_wallet(WalletId.MBBANK).balance, 1_780_000)
        self.assertEqual(e1.store.get_wallet(WalletId.MOMO).balance, 100_000)
        self.assertEqual(e1.store.list_transactions()[0].description, "FPT Telecom")

        # Order 2: MoMo payment arrives first, MBBank MOMO-CASHIN arrives 5s later
        e2 = ExpenseEngine()
        e2.reconcile_balances({WalletId.MBBANK: 2_000_000, WalletId.MOMO: 100_000}, now=t0)
        e2.ingest_notification(
            RawNotification(
                source_app=WalletId.MOMO,
                title="Thanh toán thành công",
                body="Bạn đã thanh toán thành công 220.000đ cho dịch vụ FPT Telecom.",
                received_at=t0 + timedelta(seconds=2),
            )
        )
        r_mb = e2.ingest_notification(
            RawNotification(
                source_app=WalletId.MBBANK,
                title="Biến động số dư",
                body=(
                    "TK 0901234567|GD: -220,000VND 21/11/26 14:00|"
                    "SD: 1,780,000VND| ND: MOMO-CASHIN - Ma giao dich/ Trace 900333"
                ),
                received_at=t0 + timedelta(seconds=7),
            )
        )
        self.assertEqual(r_mb.status, "DUPLICATE")
        self.assertEqual(len(e2.store.list_transactions()), 1)
        self.assertEqual(e2.store.get_wallet(WalletId.MBBANK).balance, 1_780_000)
        self.assertEqual(e2.store.get_wallet(WalletId.MOMO).balance, 100_000)
        self.assertEqual(e2.store.list_transactions()[0].source_wallet_id, WalletId.MBBANK)
        self.assertEqual(e2.store.list_transactions()[0].description, "FPT Telecom")

    def test_mbbank_two_account_self_transfer_and_sd_discrepancy(self) -> None:
        engine = ExpenseEngine()
        t0 = datetime(2026, 11, 21, 15, 0, 0)
        engine.reconcile_balances({WalletId.MBBANK: 5_000_000, WalletId.MOMO: 200_000}, now=t0)

        # #7) User transfers 1,000,000 between own TK A and TK B on MBBank
        engine.ingest_notification(
            RawNotification(
                source_app=WalletId.MBBANK,
                title="Biến động số dư",
                body="TK 0901234567|GD: -1,000,000VND 21/11/26 15:05|SD: 4,000,000VND| ND: Chuyen sang TK phu - Trace 101010",
                received_at=t0 + timedelta(minutes=5),
            )
        )
        r2 = engine.ingest_notification(
            RawNotification(
                source_app=WalletId.MBBANK,
                title="Biến động số dư",
                body="TK 88886666|GD: +1,000,000VND 21/11/26 15:05|SD: 1,000,000VND| ND: Nhan tu TK chinh - Trace 101011",
                received_at=t0 + timedelta(minutes=5, seconds=4),
            )
        )
        self.assertEqual(r2.status, "DUPLICATE")
        self.assertEqual(len(engine.store.list_transactions()), 1)
        self.assertEqual(engine.store.get_wallet(WalletId.MBBANK).balance, 5_000_000)
        summary = engine.get_dashboard_summary(year=2026, month=11, now=t0)
        self.assertEqual(summary.monthly_expense, 0)
        self.assertEqual(summary.monthly_income, 0)

        # #9) Missed notification causes MBBank SD: discrepancy -> detected immediately
        engine.ingest_notification(
            RawNotification(
                source_app=WalletId.MBBANK,
                title="Biến động số dư",
                body="TK 0901234567|GD: -50,000VND 21/11/26 16:00|SD: 4,850,000VND| ND: Cafe - Trace 202020",
                received_at=t0 + timedelta(hours=1),
                location_name="Đường Nguyễn Huệ, Q.1",
                latitude=10.7745,
                longitude=106.7035,
            )
        )
        discrepancy = engine.detect_mbbank_discrepancy()
        assert discrepancy is not None
        self.assertEqual(discrepancy.reported_balance, 4_850_000)
        self.assertEqual(discrepancy.app_balance, 4_950_000)
        self.assertEqual(discrepancy.delta, -100_000)
        self.assertEqual(engine.store.list_transactions()[0].location_name, "Đường Nguyễn Huệ, Q.1")

        # After reconciling -> discrepancy clears
        engine.reconcile_balances(
            {WalletId.MBBANK: 4_850_000, WalletId.MOMO: 200_000},
            now=t0 + timedelta(hours=1, minutes=5),
        )
        self.assertIsNone(engine.detect_mbbank_discrepancy())


if __name__ == "__main__":
    unittest.main()
