"""Main orchestration facade for the offline expense tracker core logic."""

from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime
from typing import Dict, List, Optional
from uuid import uuid4

from core.balance import (
    apply_transaction_balances,
    get_next_reconciliation_reminder,
    reconcile_wallet_balances,
    reverse_transaction_balances,
)
from core.models import (
    BalanceReconciliation,
    Direction,
    NotificationPrompt,
    RawNotification,
    Tag,
    Transaction,
    TransactionStatus,
    TransactionType,
    WalletAccount,
    WalletId,
)
from core.parser import ParsedTransaction, parse_notification
from core.store import InMemoryStore, Store


@dataclass(frozen=True)
class IngestResult:
    """Outcome of processing an incoming push notification."""

    status: str  # "CREATED" | "IGNORED" | "DUPLICATE"
    transaction: Optional[Transaction] = None
    prompt: Optional[NotificationPrompt] = None
    reason: Optional[str] = None


@dataclass(frozen=True)
class DashboardSummary:
    """Aggregated balances, pending queue count, and monthly totals."""

    mbbank_balance: int
    momo_balance: int
    total_balance: int
    pending_count: int
    monthly_expense: int
    monthly_income: int
    expense_by_tag: Dict[str, int]
    next_reconciliation_reminder: datetime


def _format_vnd(amount: int) -> str:
    return f"{amount:,}đ".replace(",", ".")


class ExpenseEngine:
    """Stateless-facade core engine backed by an offline Store."""

    def __init__(
        self,
        store: Optional[Store] = None,
        sync_mbbank_reported_balance: bool = False,
    ) -> None:
        self.store: Store = store if store is not None else InMemoryStore()
        self.sync_mbbank_reported_balance = sync_mbbank_reported_balance

    def ingest_notification(self, raw: RawNotification) -> IngestResult:
        """Parse an MBBank/MoMo notification, update balances, and build user prompt."""
        parsed = parse_notification(raw)
        if parsed is None:
            return IngestResult(
                status="IGNORED",
                reason="Notification is promotional, OTP, or not a valid transaction.",
            )

        if self._is_duplicate_notification(raw, parsed):
            return IngestResult(
                status="DUPLICATE",
                reason="Matching transaction already recorded within deduplication window.",
            )

        created_at = raw.received_at
        raw_text = f"{raw.title} | {raw.body}".strip(" |")

        if parsed.tx_type == TransactionType.INTERNAL_TRANSFER:
            tx = Transaction(
                id=str(uuid4()),
                tx_type=TransactionType.INTERNAL_TRANSFER,
                source_wallet_id=parsed.source_wallet_id,
                target_wallet_id=parsed.target_wallet_id,
                amount=parsed.amount,
                direction=parsed.direction,
                description=parsed.description,
                status=TransactionStatus.CONFIRMED,
                is_manual=False,
                trace_id=parsed.trace_id,
                raw_notification_text=raw_text,
                reported_balance_after=parsed.reported_balance_after,
                occurred_at=parsed.occurred_at,
                created_at=created_at,
                confirmed_at=created_at,
            )
            apply_transaction_balances(
                self.store, tx, sync_reported_balance=self.sync_mbbank_reported_balance
            )
            self.store.save_transaction(tx)
            return IngestResult(
                status="CREATED",
                transaction=tx,
                prompt=NotificationPrompt(
                    should_prompt=False,
                    transaction_id=tx.id,
                    title="Chuyển tiền nội bộ",
                    body=(
                        f"{parsed.source_wallet_id.value} -> "
                        f"{parsed.target_wallet_id.value if parsed.target_wallet_id else ''}: "
                        f"{_format_vnd(tx.amount)}"
                    ),
                ),
            )

        tx = Transaction(
            id=str(uuid4()),
            tx_type=parsed.tx_type,
            source_wallet_id=parsed.source_wallet_id,
            target_wallet_id=None,
            amount=parsed.amount,
            direction=parsed.direction,
            description=parsed.description,
            status=TransactionStatus.PENDING,
            is_manual=False,
            trace_id=parsed.trace_id,
            raw_notification_text=raw_text,
            reported_balance_after=parsed.reported_balance_after,
            occurred_at=parsed.occurred_at,
            created_at=created_at,
        )
        apply_transaction_balances(
            self.store, tx, sync_reported_balance=self.sync_mbbank_reported_balance
        )
        self.store.save_transaction(tx)

        return IngestResult(
            status="CREATED",
            transaction=tx,
            prompt=self._build_prompt(tx),
        )

    def confirm_transaction(
        self,
        tx_id: str,
        tag_id: str,
        note: str = "",
        now: Optional[datetime] = None,
    ) -> Transaction:
        """Assign tag and optional note to a transaction and mark it CONFIRMED."""
        tx = self.store.get_transaction(tx_id)
        if tx is None:
            raise KeyError(f"Transaction not found: {tx_id}")
        if tx.tx_type == TransactionType.INTERNAL_TRANSFER:
            raise ValueError("Cannot assign expense/income tag to an internal transfer")

        tag = self.store.get_tag(tag_id)
        if tag is None:
            raise KeyError(f"Tag not found: {tag_id}")

        ts = now or datetime.now()
        tx.tag_id = tag.id
        tx.note = note.strip()
        tx.status = TransactionStatus.CONFIRMED
        tx.confirmed_at = ts
        self.store.save_transaction(tx)
        return tx

    def add_manual_transaction(
        self,
        wallet_id: WalletId,
        direction: Direction,
        amount: int,
        tag_id: str,
        description: str = "",
        note: str = "",
        occurred_at: Optional[datetime] = None,
    ) -> Transaction:
        """Manually record a transaction (e.g., spending from MoMo wallet balance)."""
        if amount <= 0:
            raise ValueError("Transaction amount must be positive")
        tag = self.store.get_tag(tag_id)
        if tag is None:
            raise KeyError(f"Tag not found: {tag_id}")

        ts = occurred_at or datetime.now()
        tx_type = (
            TransactionType.EXPENSE if direction == Direction.OUT else TransactionType.INCOME
        )

        tx = Transaction(
            id=str(uuid4()),
            tx_type=tx_type,
            source_wallet_id=wallet_id,
            amount=amount,
            direction=direction,
            description=description.strip() if description.strip() else "Nhập tay",
            tag_id=tag.id,
            status=TransactionStatus.CONFIRMED,
            note=note.strip(),
            is_manual=True,
            occurred_at=ts,
            created_at=ts,
            confirmed_at=ts,
        )
        apply_transaction_balances(self.store, tx, sync_reported_balance=False)
        self.store.save_transaction(tx)
        return tx

    def delete_transaction(self, tx_id: str) -> bool:
        """Delete a transaction and revert its balance impact."""
        tx = self.store.get_transaction(tx_id)
        if tx is None:
            return False
        reverse_transaction_balances(self.store, tx)
        return self.store.delete_transaction(tx_id)

    def add_custom_tag(self, name: str, now: Optional[datetime] = None) -> Tag:
        """Create a new custom tag, preventing case-insensitive duplicates."""
        cleaned = " ".join(name.strip().split())
        if not cleaned:
            raise ValueError("Tag name cannot be empty")

        for existing in self.store.list_tags():
            if existing.name.casefold() == cleaned.casefold():
                raise ValueError(f"Tag '{existing.name}' already exists")

        existing_tags = self.store.list_tags()
        next_order = max((t.sort_order for t in existing_tags), default=-1) + 1
        tag = Tag(
            id=f"tag_custom_{uuid4().hex[:8]}",
            name=cleaned,
            is_default=False,
            sort_order=next_order,
            created_at=now or datetime.now(),
        )
        self.store.save_tag(tag)
        return tag

    def reconcile_balances(
        self,
        actual_balances: Dict[WalletId, int],
        note: str = "",
        now: Optional[datetime] = None,
    ) -> List[BalanceReconciliation]:
        """Reconcile actual balances (typically at month-end 12:00 PM reminder)."""
        return reconcile_wallet_balances(
            self.store, actual_balances, now or datetime.now(), note=note
        )

    def list_pending_transactions(self) -> List[Transaction]:
        """Return uncategorized transactions waiting in the in-app inbox."""
        return [
            tx
            for tx in self.store.list_transactions()
            if tx.status == TransactionStatus.PENDING
        ]

    def list_wallets(self) -> List[WalletAccount]:
        return self.store.list_wallets()

    def list_tags(self) -> List[Tag]:
        return self.store.list_tags()

    def get_dashboard_summary(
        self,
        year: Optional[int] = None,
        month: Optional[int] = None,
        now: Optional[datetime] = None,
    ) -> DashboardSummary:
        """Compute wallet balances, pending count, and monthly expense/income totals."""
        ref = now or datetime.now()
        target_year = year or ref.year
        target_month = month or ref.month

        mb = self.store.get_wallet(WalletId.MBBANK)
        momo = self.store.get_wallet(WalletId.MOMO)
        all_txs = self.store.list_transactions()

        pending_count = sum(
            1 for tx in all_txs if tx.status == TransactionStatus.PENDING
        )

        monthly_expense = 0
        monthly_income = 0
        expense_by_tag: Dict[str, int] = {}
        tags_by_id = {t.id: t.name for t in self.store.list_tags()}

        for tx in all_txs:
            if tx.occurred_at.year != target_year or tx.occurred_at.month != target_month:
                continue
            if tx.tx_type == TransactionType.EXPENSE:
                monthly_expense += tx.amount
                label = (
                    tags_by_id.get(tx.tag_id, "Chưa phân loại")
                    if tx.tag_id
                    else "Chưa phân loại"
                )
                expense_by_tag[label] = expense_by_tag.get(label, 0) + tx.amount
            elif tx.tx_type == TransactionType.INCOME:
                monthly_income += tx.amount

        return DashboardSummary(
            mbbank_balance=mb.balance,
            momo_balance=momo.balance,
            total_balance=mb.balance + momo.balance,
            pending_count=pending_count,
            monthly_expense=monthly_expense,
            monthly_income=monthly_income,
            expense_by_tag=expense_by_tag,
            next_reconciliation_reminder=get_next_reconciliation_reminder(ref),
        )

    def _is_duplicate_notification(
        self, raw: RawNotification, parsed: ParsedTransaction
    ) -> bool:
        raw_text = f"{raw.title} | {raw.body}".strip(" |")
        for existing in self.store.list_transactions():
            # 1) Exact MBBank Trace ID match from the same wallet.
            if (
                parsed.trace_id
                and existing.trace_id == parsed.trace_id
                and existing.source_wallet_id == parsed.source_wallet_id
            ):
                return True

            delta_seconds = abs(
                (parsed.occurred_at - existing.occurred_at).total_seconds()
            )

            # 2) Same raw notification delivered twice within 10s.
            if (
                delta_seconds <= 10
                and existing.source_wallet_id == parsed.source_wallet_id
                and existing.amount == parsed.amount
                and existing.direction == parsed.direction
                and existing.raw_notification_text == raw_text
            ):
                return True

            # 3) Cross-app guard if MoMo also notifies after MBBank CASHIN/CASHOUT.
            if (
                existing.tx_type == TransactionType.INTERNAL_TRANSFER
                and delta_seconds <= 120
                and existing.amount == parsed.amount
                and raw.source_app == WalletId.MOMO
            ):
                if (
                    "MOMO-CASHIN" in existing.description
                    and parsed.direction == Direction.IN
                ) or (
                    "MOMO-CASHOUT" in existing.description
                    and parsed.direction == Direction.OUT
                ):
                    return True

        return False

    def _build_prompt(self, tx: Transaction) -> NotificationPrompt:
        source_label = "MBBank" if tx.source_wallet_id == WalletId.MBBANK else "MoMo"
        sign = "-" if tx.direction == Direction.OUT else "+"
        action_verb = "chi" if tx.direction == Direction.OUT else "nhận"
        desc = (
            f" ({tx.description})"
            if tx.description and tx.description != "Không rõ nội dung"
            else ""
        )

        return NotificationPrompt(
            should_prompt=True,
            transaction_id=tx.id,
            title=f"{source_label} {sign}{_format_vnd(tx.amount)}",
            body=f"Bạn vừa {action_verb} {_format_vnd(tx.amount)}{desc}. Chạm để chọn tag & ghi chú.",
        )
