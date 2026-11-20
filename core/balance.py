"""Wallet balance mutations, reconciliation, and month-end reminder scheduling."""

from __future__ import annotations

import calendar
from datetime import date, datetime, timedelta
from typing import Dict
from uuid import uuid4

from core.models import BalanceReconciliation, Transaction, TransactionType, WalletId
from core.store import Store


def _apply_delta(store: Store, tx: Transaction, multiplier: int) -> None:
    """Apply (+1) or reverse (-1) a transaction's effect on wallet balances."""
    if tx.tx_type == TransactionType.EXPENSE:
        wallet = store.get_wallet(tx.source_wallet_id)
        wallet.balance -= multiplier * tx.amount
        store.save_wallet(wallet)
        return

    if tx.tx_type == TransactionType.INCOME:
        wallet = store.get_wallet(tx.source_wallet_id)
        wallet.balance += multiplier * tx.amount
        store.save_wallet(wallet)
        return

    if tx.tx_type == TransactionType.INTERNAL_TRANSFER:
        if tx.target_wallet_id is None:
            raise ValueError("Internal transfer must define target_wallet_id")
        src = store.get_wallet(tx.source_wallet_id)
        dst = store.get_wallet(tx.target_wallet_id)
        src.balance -= multiplier * tx.amount
        dst.balance += multiplier * tx.amount
        store.save_wallet(src)
        store.save_wallet(dst)
        return

    raise ValueError(f"Unsupported transaction type: {tx.tx_type}")


def apply_transaction_balances(
    store: Store, tx: Transaction, sync_reported_balance: bool = False
) -> None:
    """Apply a transaction's monetary impact to affected wallets."""
    _apply_delta(store, tx, multiplier=1)

    # Optionally calibrate MBBank balance using explicit SD: value from notification.
    if (
        sync_reported_balance
        and tx.reported_balance_after is not None
        and tx.source_wallet_id == WalletId.MBBANK
    ):
        mb = store.get_wallet(WalletId.MBBANK)
        mb.balance = tx.reported_balance_after
        store.save_wallet(mb)
    elif (
        sync_reported_balance
        and tx.reported_balance_after is not None
        and tx.target_wallet_id == WalletId.MBBANK
    ):
        mb = store.get_wallet(WalletId.MBBANK)
        mb.balance = tx.reported_balance_after
        store.save_wallet(mb)


def reverse_transaction_balances(store: Store, tx: Transaction) -> None:
    """Reverse a transaction's monetary impact when editing or deleting."""
    _apply_delta(store, tx, multiplier=-1)


def reconcile_wallet_balances(
    store: Store,
    actual_balances: Dict[WalletId, int],
    reconciled_at: datetime,
    note: str = "",
) -> list[BalanceReconciliation]:
    """Record actual end-of-month balances and capture any unrecorded discrepancy."""
    records: list[BalanceReconciliation] = []
    for wallet_id, actual in actual_balances.items():
        if actual < 0:
            raise ValueError(f"Actual balance for {wallet_id.value} cannot be negative")

        wallet = store.get_wallet(wallet_id)
        expected = wallet.balance
        discrepancy = actual - expected

        rec = BalanceReconciliation(
            id=str(uuid4()),
            wallet_id=wallet_id,
            expected_balance=expected,
            actual_balance=actual,
            discrepancy=discrepancy,
            reconciled_at=reconciled_at,
            note=note,
        )
        store.save_reconciliation(rec)

        wallet.balance = actual
        wallet.last_reconciled_balance = actual
        wallet.last_reconciled_at = reconciled_at
        store.save_wallet(wallet)

        records.append(rec)
    return records


def calculate_month_end_reminder(year: int, month: int) -> datetime:
    """Return 12:00 PM on the last weekday of (year, month).

    If the last calendar day falls on Saturday or Sunday, shift back to Friday.
    """
    last_day_num = calendar.monthrange(year, month)[1]
    target_date = date(year, month, last_day_num)
    weekday = target_date.weekday()  # Mon=0 .. Fri=4, Sat=5, Sun=6

    if weekday == 5:
        target_date -= timedelta(days=1)
    elif weekday == 6:
        target_date -= timedelta(days=2)

    return datetime(target_date.year, target_date.month, target_date.day, 12, 0, 0)


def get_next_reconciliation_reminder(now: datetime) -> datetime:
    """Return the next upcoming month-end balance reminder at 12:00 PM."""
    candidate = calculate_month_end_reminder(now.year, now.month)
    if now < candidate:
        return candidate

    next_year, next_month = (
        (now.year + 1, 1) if now.month == 12 else (now.year, now.month + 1)
    )
    return calculate_month_end_reminder(next_year, next_month)
