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


if __name__ == "__main__":
    unittest.main()
