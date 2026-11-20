"""Domain models and default seed data for the expense tracker core engine."""

from __future__ import annotations

from dataclasses import dataclass, field
from datetime import datetime
from enum import Enum
from typing import Optional


class WalletId(str, Enum):
    """Supported money sources in Phase 1."""

    MBBANK = "MBBANK"
    MOMO = "MOMO"


class Direction(str, Enum):
    """Cash flow direction relative to a wallet."""

    OUT = "OUT"
    IN = "IN"


class TransactionType(str, Enum):
    """High-level accounting classification of a transaction."""

    EXPENSE = "EXPENSE"
    INCOME = "INCOME"
    INTERNAL_TRANSFER = "INTERNAL_TRANSFER"


class TransactionStatus(str, Enum):
    """User confirmation state of a transaction."""

    PENDING = "PENDING"
    CONFIRMED = "CONFIRMED"


DEFAULT_TAG_SPECS: tuple[tuple[str, str], ...] = (
    ("tag_an_uong", "Ăn uống"),
    ("tag_cf", "CF"),
    ("tag_di_chuyen", "Di chuyển"),
    ("tag_mua_sam", "Mua sắm"),
    ("tag_hoa_don", "Hóa đơn"),
    ("tag_giai_tri", "Giải trí"),
    ("tag_tra_no", "Trả nợ"),
    ("tag_thu_nhap", "Thu nhập"),
    ("tag_hoan_tien", "Hoàn tiền / Được trả"),
)


@dataclass
class WalletAccount:
    """Represents a tracked wallet or bank account."""

    id: WalletId
    name: str
    balance: int = 0
    last_reconciled_balance: int = 0
    last_reconciled_at: Optional[datetime] = None


@dataclass
class Tag:
    """Unified category tag for both expenses and incoming transactions."""

    id: str
    name: str
    is_default: bool = False
    sort_order: int = 0
    created_at: datetime = field(default_factory=datetime.now)


@dataclass
class Transaction:
    """A financial event parsed from a notification or added manually."""

    id: str
    tx_type: TransactionType
    source_wallet_id: WalletId
    amount: int
    direction: Direction
    description: str
    occurred_at: datetime
    created_at: datetime
    status: TransactionStatus = TransactionStatus.PENDING
    target_wallet_id: Optional[WalletId] = None
    tag_id: Optional[str] = None
    note: str = ""
    is_manual: bool = False
    trace_id: Optional[str] = None
    raw_notification_text: Optional[str] = None
    reported_balance_after: Optional[int] = None
    confirmed_at: Optional[datetime] = None


@dataclass
class BalanceReconciliation:
    """Snapshot recorded when the user reconciles actual wallet balance."""

    id: str
    wallet_id: WalletId
    expected_balance: int
    actual_balance: int
    discrepancy: int
    reconciled_at: datetime
    note: str = ""


@dataclass(frozen=True)
class RawNotification:
    """Incoming push notification payload forwarded by iOS Shortcuts."""

    source_app: WalletId
    title: str
    body: str
    received_at: datetime = field(default_factory=datetime.now)


@dataclass(frozen=True)
class NotificationPrompt:
    """Instruction describing the local notification to display to the user."""

    should_prompt: bool
    transaction_id: str
    title: str
    body: str
