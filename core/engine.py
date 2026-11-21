"""Main orchestration facade for the offline expense tracker core logic."""

from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime
import re
from typing import Dict, List, Optional
import unicodedata
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
from core.suggester import suggest_tags as _suggest_tags


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


@dataclass(frozen=True)
class MBBankBalanceDiscrepancy:
    """Discrepancy between MBBank's latest SD: balance and app balance."""

    reported_balance: int
    app_balance: int
    delta: int
    reported_at: datetime


def _format_vnd(amount: int) -> str:
    return f"{amount:,}đ".replace(",", ".")


_CROSS_APP_WINDOW_SECONDS = 120.0
_SAME_BANK_SELF_TRANSFER_WINDOW_SECONDS = 30.0
_CROSS_APP_MERGE_DELIMITER = " || "
_MB_ACCOUNT_RE = re.compile(r"\bTK\s+(?P<acct>[A-Z0-9x*]+)", re.IGNORECASE)

_MBBANK_MOMO_GATEWAY_MARKERS: tuple[str, ...] = (
    "MOMO",
    "M_SERVICE",
    "MSERVICE",
    "M SERVICE",
    "VI MOMO",
    "AP-CASHIN",
    "AP CASHIN",
    "BANK2WALLET",
    "NAPAS",
)

_MOMO_LINKED_PAYMENT_MARKERS: tuple[str, ...] = (
    "THANH TOAN",
    "CHO DICH VU",
    "LIEN KET",
    "NGAN HANG",
    "MBBANK",
    "MB BANK",
    "APPLE",
    "GRAB",
    "GOOGLE",
    "SPOTIFY",
    "NETFLIX",
    "YOUTUBE",
    "ICLOUD",
    "APP STORE",
)

_GENERIC_BANK_DESC_MARKERS: tuple[str, ...] = (
    "MOMO",
    "M_SERVICE",
    "MSERVICE",
    "M SERVICE",
    "THANH TOAN",
    "TT ",
    "KHONG RO NOI DUNG",
)


def _normalized_upper(text: str) -> str:
    replaced = text.replace("đ", "d").replace("Đ", "D")
    decomposed = unicodedata.normalize("NFD", replaced)
    ascii_only = "".join(ch for ch in decomposed if unicodedata.category(ch) != "Mn")
    return ascii_only.upper()


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

        # Reconcile cross-app linked-bank expense (e.g., Apple Services / Grab / WiFi bill
        # paid through MoMo using linked MBBank account) regardless of arrival order or
        # whether MBBank labels the debit as MOMO-CASHIN.
        reconciled = self._reconcile_cross_app_linked_expense(raw, parsed, raw_text)
        if reconciled is not None:
            return reconciled

        # Detect self-transfer between two different MBBank accounts of the same user.
        self_transfer = self._reconcile_same_bank_self_transfer(raw, parsed, raw_text)
        if self_transfer is not None:
            return self_transfer

        clean_location_name = (
            " ".join(raw.location_name.strip().split()) if raw.location_name else None
        ) or None

        if parsed.tx_type == TransactionType.INTERNAL_TRANSFER:
            # Self-heal if MoMo fired its wallet-side notification a few seconds
            # before MBBank's authoritative MOMO-CASHIN / MOMO-CASHOUT notification.
            self._remove_premature_momo_transfer_leg(raw, parsed)

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
                location_name=clean_location_name,
                latitude=raw.latitude,
                longitude=raw.longitude,
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
            location_name=clean_location_name,
            latitude=raw.latitude,
            longitude=raw.longitude,
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

    def update_transaction(
        self,
        tx_id: str,
        wallet_id: WalletId,
        direction: Direction,
        amount: int,
        tag_id: str,
        description: str,
        note: str,
        occurred_at: datetime,
        now: Optional[datetime] = None,
    ) -> Transaction:
        """Update editable transaction fields while keeping wallet balances exact."""
        existing = self.store.get_transaction(tx_id)
        if existing is None:
            raise KeyError(f"Transaction not found: {tx_id}")
        if amount <= 0:
            raise ValueError("Transaction amount must be positive")
        tag = self.store.get_tag(tag_id)
        if tag is None:
            raise KeyError(f"Tag not found: {tag_id}")

        reverse_transaction_balances(self.store, existing)

        existing.source_wallet_id = wallet_id
        existing.target_wallet_id = None
        existing.direction = direction
        existing.tx_type = (
            TransactionType.EXPENSE if direction == Direction.OUT else TransactionType.INCOME
        )
        existing.amount = amount
        clean_desc = description.strip()
        if clean_desc:
            existing.description = clean_desc
        existing.tag_id = tag.id
        existing.note = note.strip()
        existing.occurred_at = occurred_at
        existing.status = TransactionStatus.CONFIRMED
        existing.confirmed_at = existing.confirmed_at or (now or datetime.now())

        apply_transaction_balances(self.store, existing, sync_reported_balance=False)
        self.store.save_transaction(existing)
        return existing

    def suggest_tags(self, tx: Transaction, limit: int = 3) -> List[Tag]:
        return _suggest_tags(
            tx=tx,
            history=self.store.list_transactions(),
            available_tags=self.store.list_tags(),
            limit=limit,
        )

    def detect_mbbank_discrepancy(self) -> Optional[MBBankBalanceDiscrepancy]:
        mb = self.store.get_wallet(WalletId.MBBANK)
        mb_txs = [
            tx
            for tx in self.store.list_transactions()
            if tx.source_wallet_id == WalletId.MBBANK or tx.target_wallet_id == WalletId.MBBANK
        ]
        if not mb_txs:
            return None
        newest = mb_txs[0]
        if newest.reported_balance_after is None:
            return None
        if newest.tx_type == TransactionType.INTERNAL_TRANSFER and newest.target_wallet_id == WalletId.MBBANK:
            return None
        if mb.last_reconciled_at is not None and mb.last_reconciled_at >= newest.occurred_at:
            return None
        if newest.reported_balance_after == mb.balance:
            return None
        return MBBankBalanceDiscrepancy(
            reported_balance=newest.reported_balance_after,
            app_balance=mb.balance,
            delta=newest.reported_balance_after - mb.balance,
            reported_at=newest.occurred_at,
        )

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

    def _extract_mb_account_number(self, text: Optional[str]) -> Optional[str]:
        if not text:
            return None
        match = _MB_ACCOUNT_RE.search(text)
        return match.group("acct").upper() if match else None

    def _reconcile_same_bank_self_transfer(
        self, raw: RawNotification, parsed: ParsedTransaction, raw_text: str
    ) -> Optional[IngestResult]:
        if raw.source_app != WalletId.MBBANK:
            return None
        if parsed.tx_type not in (TransactionType.EXPENSE, TransactionType.INCOME):
            return None
        incoming_acct = self._extract_mb_account_number(raw_text)
        if not incoming_acct:
            return None

        for existing in self.store.list_transactions():
            if existing.is_manual or existing.source_wallet_id != WalletId.MBBANK:
                continue
            if existing.tx_type not in (TransactionType.EXPENSE, TransactionType.INCOME):
                continue
            if existing.direction == parsed.direction or existing.amount != parsed.amount:
                continue
            if (
                existing.raw_notification_text
                and _CROSS_APP_MERGE_DELIMITER in existing.raw_notification_text
            ):
                continue
            occurred_delta = abs((parsed.occurred_at - existing.occurred_at).total_seconds())
            received_delta = abs((raw.received_at - existing.created_at).total_seconds())
            if min(occurred_delta, received_delta) > _SAME_BANK_SELF_TRANSFER_WINDOW_SECONDS:
                continue
            existing_acct = self._extract_mb_account_number(existing.raw_notification_text)
            if not existing_acct or existing_acct == incoming_acct:
                continue

            reverse_transaction_balances(self.store, existing)
            existing.tx_type = TransactionType.INTERNAL_TRANSFER
            existing.source_wallet_id = WalletId.MBBANK
            existing.target_wallet_id = WalletId.MBBANK
            existing.direction = Direction.OUT
            existing.status = TransactionStatus.CONFIRMED
            existing.confirmed_at = raw.received_at
            existing.description = "Chuyển giữa 2 TK MBBank"
            existing.raw_notification_text = _CROSS_APP_MERGE_DELIMITER.join(
                part for part in (existing.raw_notification_text, raw_text) if part
            )
            self.store.save_transaction(existing)
            return IngestResult(
                status="DUPLICATE",
                transaction=existing,
                reason="Merged opposite-direction MBBank notifications across two own accounts into an internal self-transfer.",
            )
        return None

    def _is_within_cross_app_window(
        self, existing: Transaction, raw: RawNotification, parsed: ParsedTransaction
    ) -> bool:
        occurred_delta = abs((parsed.occurred_at - existing.occurred_at).total_seconds())
        received_delta = abs((raw.received_at - existing.created_at).total_seconds())
        return min(occurred_delta, received_delta) <= _CROSS_APP_WINDOW_SECONDS

    def _matches_linked_bank_payment(self, mbbank_text: str, momo_text: str) -> bool:
        mb_upper = _normalized_upper(mbbank_text)
        momo_upper = _normalized_upper(momo_text)
        return any(m in mb_upper for m in _MBBANK_MOMO_GATEWAY_MARKERS) or any(
            m in momo_upper for m in _MOMO_LINKED_PAYMENT_MARKERS
        )

    def _should_upgrade_bank_description(
        self, current_desc: str, momo_desc: str
    ) -> bool:
        if not momo_desc or momo_desc == "Không rõ nội dung":
            return False
        if not current_desc or current_desc == "Không rõ nội dung":
            return True
        current_upper = _normalized_upper(current_desc)
        return any(m in current_upper for m in _GENERIC_BANK_DESC_MARKERS)

    def _reconcile_cross_app_linked_expense(
        self, raw: RawNotification, parsed: ParsedTransaction, raw_text: str
    ) -> Optional[IngestResult]:
        # Case A: Incoming MBBank MOMO-CASHIN arriving right after a MoMo bill payment
        # expense of the exact same amount -> re-home the MoMo expense to MBBank.
        if (
            parsed.tx_type == TransactionType.INTERNAL_TRANSFER
            and parsed.source_wallet_id == WalletId.MBBANK
            and parsed.target_wallet_id == WalletId.MOMO
        ):
            for existing in self.store.list_transactions():
                if existing.is_manual:
                    continue
                if (
                    existing.tx_type != TransactionType.EXPENSE
                    or existing.direction != Direction.OUT
                    or existing.source_wallet_id != WalletId.MOMO
                    or existing.amount != parsed.amount
                ):
                    continue
                if (
                    existing.raw_notification_text
                    and _CROSS_APP_MERGE_DELIMITER in existing.raw_notification_text
                ):
                    continue
                if not self._is_within_cross_app_window(existing, raw, parsed):
                    continue

                reverse_transaction_balances(self.store, existing)
                existing.source_wallet_id = WalletId.MBBANK
                existing.target_wallet_id = None
                if parsed.trace_id:
                    existing.trace_id = parsed.trace_id
                if parsed.reported_balance_after is not None:
                    existing.reported_balance_after = parsed.reported_balance_after
                existing.occurred_at = parsed.occurred_at
                existing.raw_notification_text = _CROSS_APP_MERGE_DELIMITER.join(
                    part for part in (existing.raw_notification_text, raw_text) if part
                )
                apply_transaction_balances(
                    self.store,
                    existing,
                    sync_reported_balance=self.sync_mbbank_reported_balance,
                )
                self.store.save_transaction(existing)
                return IngestResult(
                    status="DUPLICATE",
                    transaction=existing,
                    reason="Re-homed MoMo bill payment to MBBank from matching MOMO-CASHIN.",
                )
            return None

        if parsed.tx_type != TransactionType.EXPENSE or parsed.direction != Direction.OUT:
            return None

        for existing in self.store.list_transactions():
            if existing.is_manual:
                continue
            if existing.amount != parsed.amount:
                continue
            if (
                existing.raw_notification_text
                and _CROSS_APP_MERGE_DELIMITER in existing.raw_notification_text
            ):
                continue
            if not self._is_within_cross_app_window(existing, raw, parsed):
                continue

            # Case B: MBBank MOMO-CASHIN arrived first, then MoMo bill payment expense
            # arrived within 120s -> convert internal transfer into an MBBank expense.
            if (
                parsed.source_wallet_id == WalletId.MOMO
                and existing.tx_type == TransactionType.INTERNAL_TRANSFER
                and existing.source_wallet_id == WalletId.MBBANK
                and existing.target_wallet_id == WalletId.MOMO
            ):
                reverse_transaction_balances(self.store, existing)
                existing.tx_type = TransactionType.EXPENSE
                existing.source_wallet_id = WalletId.MBBANK
                existing.target_wallet_id = None
                existing.direction = Direction.OUT
                existing.status = TransactionStatus.PENDING
                existing.confirmed_at = None
                if parsed.description and parsed.description != "Không rõ nội dung":
                    existing.description = parsed.description
                existing.raw_notification_text = _CROSS_APP_MERGE_DELIMITER.join(
                    part for part in (existing.raw_notification_text, raw_text) if part
                )
                apply_transaction_balances(
                    self.store,
                    existing,
                    sync_reported_balance=self.sync_mbbank_reported_balance,
                )
                self.store.save_transaction(existing)
                return IngestResult(
                    status="CREATED",
                    transaction=existing,
                    prompt=self._build_prompt(existing),
                    reason="Converted MOMO-CASHIN internal transfer into MBBank expense using MoMo payment notification.",
                )

            if (
                existing.tx_type != TransactionType.EXPENSE
                or existing.direction != Direction.OUT
                or existing.source_wallet_id == parsed.source_wallet_id
            ):
                continue

            # Order 1: MBBank arrived first, MoMo arrived second -> keep MBBank deduction,
            # leave Ví MoMo untouched, and enrich description with MoMo's merchant name.
            if (
                existing.source_wallet_id == WalletId.MBBANK
                and parsed.source_wallet_id == WalletId.MOMO
            ):
                mb_text = f"{existing.description} {existing.raw_notification_text or ''}"
                momo_text = f"{parsed.description} {raw_text}"
                if not self._matches_linked_bank_payment(mb_text, momo_text):
                    continue

                if self._should_upgrade_bank_description(
                    existing.description, parsed.description
                ):
                    existing.description = parsed.description
                existing.raw_notification_text = _CROSS_APP_MERGE_DELIMITER.join(
                    part for part in (existing.raw_notification_text, raw_text) if part
                )
                self.store.save_transaction(existing)
                return IngestResult(
                    status="DUPLICATE",
                    transaction=existing,
                    reason="Merged linked MoMo payment into existing MBBank expense.",
                )

            # Order 2: MoMo arrived first, MBBank arrived second -> refund Ví MoMo,
            # re-home the transaction to MBBank, apply MBBank deduction, keep MoMo's
            # clean merchant description and any tag/note the user already picked.
            if (
                existing.source_wallet_id == WalletId.MOMO
                and parsed.source_wallet_id == WalletId.MBBANK
            ):
                mb_text = f"{parsed.description} {raw_text}"
                momo_text = f"{existing.description} {existing.raw_notification_text or ''}"
                if not self._matches_linked_bank_payment(mb_text, momo_text):
                    continue

                reverse_transaction_balances(self.store, existing)
                existing.source_wallet_id = WalletId.MBBANK
                if parsed.trace_id:
                    existing.trace_id = parsed.trace_id
                if parsed.reported_balance_after is not None:
                    existing.reported_balance_after = parsed.reported_balance_after
                existing.occurred_at = parsed.occurred_at
                if (
                    (not existing.description or existing.description == "Không rõ nội dung")
                    and parsed.description
                ):
                    existing.description = parsed.description
                existing.raw_notification_text = _CROSS_APP_MERGE_DELIMITER.join(
                    part for part in (existing.raw_notification_text, raw_text) if part
                )
                apply_transaction_balances(
                    self.store,
                    existing,
                    sync_reported_balance=self.sync_mbbank_reported_balance,
                )
                self.store.save_transaction(existing)
                return IngestResult(
                    status="DUPLICATE",
                    transaction=existing,
                    reason="Re-homed linked MoMo expense to MBBank.",
                )

        return None

    def _remove_premature_momo_transfer_leg(
        self, raw: RawNotification, parsed: ParsedTransaction
    ) -> None:
        if parsed.tx_type != TransactionType.INTERNAL_TRANSFER:
            return
        is_cashin = "MOMO-CASHIN" in parsed.description
        is_cashout = "MOMO-CASHOUT" in parsed.description
        if not (is_cashin or is_cashout):
            return

        for existing in self.store.list_transactions():
            if existing.is_manual or existing.source_wallet_id != WalletId.MOMO:
                continue
            if existing.amount != parsed.amount:
                continue
            if not self._is_within_cross_app_window(existing, raw, parsed):
                continue
            if (is_cashin and existing.tx_type == TransactionType.INCOME and existing.direction == Direction.IN) or (
                is_cashout and existing.tx_type == TransactionType.EXPENSE and existing.direction == Direction.OUT
            ):
                reverse_transaction_balances(self.store, existing)
                self.store.delete_transaction(existing.id)
                return

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
                and self._is_within_cross_app_window(existing, raw, parsed)
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
