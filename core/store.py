"""Storage abstraction with in-memory and offline JSON file implementations."""

from __future__ import annotations

import json
from datetime import datetime
from pathlib import Path
from typing import Dict, List, Optional, Protocol

from core.models import (
    DEFAULT_TAG_SPECS,
    BalanceReconciliation,
    Direction,
    Tag,
    Transaction,
    TransactionStatus,
    TransactionType,
    WalletAccount,
    WalletId,
)


class Store(Protocol):
    """Persistence contract for wallets, tags, transactions, and reconciliations."""

    def get_wallet(self, wallet_id: WalletId) -> WalletAccount: ...
    def save_wallet(self, wallet: WalletAccount) -> None: ...
    def list_wallets(self) -> List[WalletAccount]: ...

    def get_tag(self, tag_id: str) -> Optional[Tag]: ...
    def save_tag(self, tag: Tag) -> None: ...
    def list_tags(self) -> List[Tag]: ...

    def get_transaction(self, tx_id: str) -> Optional[Transaction]: ...
    def save_transaction(self, tx: Transaction) -> None: ...
    def delete_transaction(self, tx_id: str) -> bool: ...
    def list_transactions(self) -> List[Transaction]: ...

    def save_reconciliation(self, rec: BalanceReconciliation) -> None: ...
    def list_reconciliations(self) -> List[BalanceReconciliation]: ...


def _default_wallets() -> Dict[WalletId, WalletAccount]:
    return {
        WalletId.MBBANK: WalletAccount(id=WalletId.MBBANK, name="MBBank", balance=0),
        WalletId.MOMO: WalletAccount(id=WalletId.MOMO, name="Ví MoMo", balance=0),
    }


def _default_tags(now: Optional[datetime] = None) -> Dict[str, Tag]:
    ts = now or datetime.now()
    return {
        tag_id: Tag(
            id=tag_id,
            name=name,
            is_default=True,
            sort_order=idx,
            created_at=ts,
        )
        for idx, (tag_id, name) in enumerate(DEFAULT_TAG_SPECS)
    }


class InMemoryStore:
    """Fast in-memory store for automated tests and simulations."""

    def __init__(self) -> None:
        self._wallets: Dict[WalletId, WalletAccount] = _default_wallets()
        self._tags: Dict[str, Tag] = _default_tags()
        self._transactions: Dict[str, Transaction] = {}
        self._reconciliations: List[BalanceReconciliation] = []

    def get_wallet(self, wallet_id: WalletId) -> WalletAccount:
        return self._wallets[wallet_id]

    def save_wallet(self, wallet: WalletAccount) -> None:
        self._wallets[wallet.id] = wallet

    def list_wallets(self) -> List[WalletAccount]:
        return [self._wallets[WalletId.MBBANK], self._wallets[WalletId.MOMO]]

    def get_tag(self, tag_id: str) -> Optional[Tag]:
        return self._tags.get(tag_id)

    def save_tag(self, tag: Tag) -> None:
        self._tags[tag.id] = tag

    def list_tags(self) -> List[Tag]:
        return sorted(self._tags.values(), key=lambda t: (t.sort_order, t.created_at))

    def get_transaction(self, tx_id: str) -> Optional[Transaction]:
        return self._transactions.get(tx_id)

    def save_transaction(self, tx: Transaction) -> None:
        self._transactions[tx.id] = tx

    def delete_transaction(self, tx_id: str) -> bool:
        return self._transactions.pop(tx_id, None) is not None

    def list_transactions(self) -> List[Transaction]:
        return sorted(
            self._transactions.values(),
            key=lambda t: (t.occurred_at, t.created_at),
            reverse=True,
        )

    def save_reconciliation(self, rec: BalanceReconciliation) -> None:
        self._reconciliations.append(rec)

    def list_reconciliations(self) -> List[BalanceReconciliation]:
        return sorted(
            self._reconciliations, key=lambda r: r.reconciled_at, reverse=True
        )


def _dt_to_iso(dt: Optional[datetime]) -> Optional[str]:
    return dt.isoformat() if dt else None


def _iso_to_dt(raw: Optional[str]) -> Optional[datetime]:
    return datetime.fromisoformat(raw) if raw else None


class JsonFileStore(InMemoryStore):
    """Offline JSON-backed store mirroring on-device persistence."""

    def __init__(self, file_path: str | Path) -> None:
        super().__init__()
        self._path = Path(file_path)
        if self._path.exists():
            self._load()
        else:
            self._flush()

    def save_wallet(self, wallet: WalletAccount) -> None:
        super().save_wallet(wallet)
        self._flush()

    def save_tag(self, tag: Tag) -> None:
        super().save_tag(tag)
        self._flush()

    def save_transaction(self, tx: Transaction) -> None:
        super().save_transaction(tx)
        self._flush()

    def delete_transaction(self, tx_id: str) -> bool:
        deleted = super().delete_transaction(tx_id)
        if deleted:
            self._flush()
        return deleted

    def save_reconciliation(self, rec: BalanceReconciliation) -> None:
        super().save_reconciliation(rec)
        self._flush()

    def _flush(self) -> None:
        self._path.parent.mkdir(parents=True, exist_ok=True)
        payload = {
            "wallets": [
                {
                    "id": w.id.value,
                    "name": w.name,
                    "balance": w.balance,
                    "last_reconciled_balance": w.last_reconciled_balance,
                    "last_reconciled_at": _dt_to_iso(w.last_reconciled_at),
                }
                for w in self._wallets.values()
            ],
            "tags": [
                {
                    "id": t.id,
                    "name": t.name,
                    "is_default": t.is_default,
                    "sort_order": t.sort_order,
                    "created_at": _dt_to_iso(t.created_at),
                }
                for t in self._tags.values()
            ],
            "transactions": [
                {
                    "id": tx.id,
                    "tx_type": tx.tx_type.value,
                    "source_wallet_id": tx.source_wallet_id.value,
                    "target_wallet_id": tx.target_wallet_id.value
                    if tx.target_wallet_id
                    else None,
                    "amount": tx.amount,
                    "direction": tx.direction.value,
                    "description": tx.description,
                    "tag_id": tx.tag_id,
                    "note": tx.note,
                    "status": tx.status.value,
                    "is_manual": tx.is_manual,
                    "trace_id": tx.trace_id,
                    "raw_notification_text": tx.raw_notification_text,
                    "reported_balance_after": tx.reported_balance_after,
                    "occurred_at": _dt_to_iso(tx.occurred_at),
                    "created_at": _dt_to_iso(tx.created_at),
                    "confirmed_at": _dt_to_iso(tx.confirmed_at),
                }
                for tx in self._transactions.values()
            ],
            "reconciliations": [
                {
                    "id": rec.id,
                    "wallet_id": rec.wallet_id.value,
                    "expected_balance": rec.expected_balance,
                    "actual_balance": rec.actual_balance,
                    "discrepancy": rec.discrepancy,
                    "reconciled_at": _dt_to_iso(rec.reconciled_at),
                    "note": rec.note,
                }
                for rec in self._reconciliations
            ],
        }
        self._path.write_text(
            json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8"
        )

    def _load(self) -> None:
        raw = json.loads(self._path.read_text(encoding="utf-8"))

        for w in raw.get("wallets", []):
            wid = WalletId(w["id"])
            self._wallets[wid] = WalletAccount(
                id=wid,
                name=w["name"],
                balance=w["balance"],
                last_reconciled_balance=w.get("last_reconciled_balance", 0),
                last_reconciled_at=_iso_to_dt(w.get("last_reconciled_at")),
            )

        if raw.get("tags"):
            self._tags = {
                t["id"]: Tag(
                    id=t["id"],
                    name=t["name"],
                    is_default=t.get("is_default", False),
                    sort_order=t.get("sort_order", 0),
                    created_at=_iso_to_dt(t.get("created_at")) or datetime.now(),
                )
                for t in raw["tags"]
            }

        self._transactions = {
            tx["id"]: Transaction(
                id=tx["id"],
                tx_type=TransactionType(tx["tx_type"]),
                source_wallet_id=WalletId(tx["source_wallet_id"]),
                target_wallet_id=WalletId(tx["target_wallet_id"])
                if tx.get("target_wallet_id")
                else None,
                amount=tx["amount"],
                direction=Direction(tx["direction"]),
                description=tx.get("description", ""),
                tag_id=tx.get("tag_id"),
                note=tx.get("note", ""),
                status=TransactionStatus(tx["status"]),
                is_manual=tx.get("is_manual", False),
                trace_id=tx.get("trace_id"),
                raw_notification_text=tx.get("raw_notification_text"),
                reported_balance_after=tx.get("reported_balance_after"),
                occurred_at=_iso_to_dt(tx["occurred_at"]) or datetime.now(),
                created_at=_iso_to_dt(tx["created_at"]) or datetime.now(),
                confirmed_at=_iso_to_dt(tx.get("confirmed_at")),
            )
            for tx in raw.get("transactions", [])
        }

        self._reconciliations = [
            BalanceReconciliation(
                id=rec["id"],
                wallet_id=WalletId(rec["wallet_id"]),
                expected_balance=rec["expected_balance"],
                actual_balance=rec["actual_balance"],
                discrepancy=rec["discrepancy"],
                reconciled_at=_iso_to_dt(rec["reconciled_at"]) or datetime.now(),
                note=rec.get("note", ""),
            )
            for rec in raw.get("reconciliations", [])
        ]
