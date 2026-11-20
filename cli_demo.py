"""Interactive CLI simulator for testing MBBank/MoMo notifications on Windows."""

from __future__ import annotations

from datetime import datetime
from pathlib import Path

from core.engine import ExpenseEngine
from core.models import RawNotification, WalletId
from core.store import JsonFileStore


def _fmt(amount: int) -> str:
    return f"{amount:,}đ".replace(",", ".")


def main() -> None:
    store = JsonFileStore(Path("data/demo_state.json"))
    engine = ExpenseEngine(store=store)

    print("=== Outcome Core Logic Simulator ===")
    print("Lệnh hỗ trợ: init | noti | pending | confirm | summary | quit")

    while True:
        cmd = input("\n> Nhập lệnh: ").strip().lower()
        if cmd in ("quit", "exit", "q"):
            break

        if cmd == "init":
            mb = int(input("Số dư MBBank ban đầu (VND): ").strip())
            momo = int(input("Số dư MoMo ban đầu (VND): ").strip())
            engine.reconcile_balances(
                {WalletId.MBBANK: mb, WalletId.MOMO: momo}, note="CLI init"
            )
            print("Đã cập nhật số dư ban đầu.")

        elif cmd == "noti":
            src_raw = input("Nguồn (MB/MOMO): ").strip().upper()
            src = WalletId.MBBANK if src_raw in ("MB", "MBBANK") else WalletId.MOMO
            title = input("Title thông báo: ").strip()
            body = input("Body thông báo: ").strip()
            res = engine.ingest_notification(
                RawNotification(
                    source_app=src, title=title, body=body, received_at=datetime.now()
                )
            )
            print(f"Kết quả: {res.status}")
            if res.reason:
                print(f"Lý do: {res.reason}")
            if res.prompt:
                print(
                    f"Prompt [should_prompt={res.prompt.should_prompt}]: "
                    f"{res.prompt.title} — {res.prompt.body}"
                )

        elif cmd == "pending":
            items = engine.list_pending_transactions()
            if not items:
                print("Không có giao dịch nào đang chờ phân loại.")
            for tx in items:
                print(
                    f"- ID: {tx.id[:8]} | {tx.source_wallet_id.value} | "
                    f"{tx.direction.value} {_fmt(tx.amount)} | {tx.description}"
                )

        elif cmd == "confirm":
            items = engine.list_pending_transactions()
            if not items:
                print("Không có giao dịch PENDING.")
                continue
            for idx, tx in enumerate(items, 1):
                print(
                    f"{idx}. {tx.source_wallet_id.value} {tx.direction.value} "
                    f"{_fmt(tx.amount)} ({tx.description})"
                )
            pick = int(input("Chọn số thứ tự giao dịch: ").strip()) - 1
            tx = items[pick]
            tags = engine.list_tags()
            for idx, t in enumerate(tags, 1):
                print(f"  {idx}. {t.name}")
            t_pick = int(input("Chọn số thứ tự tag: ").strip()) - 1
            note = input("Ghi chú (Enter để bỏ qua): ").strip()
            engine.confirm_transaction(tx.id, tags[t_pick].id, note=note)
            print("Đã lưu giao dịch!")

        elif cmd == "summary":
            s = engine.get_dashboard_summary()
            print(
                f"MBBank: {_fmt(s.mbbank_balance)} | MoMo: {_fmt(s.momo_balance)} | "
                f"Tổng: {_fmt(s.total_balance)}"
            )
            print(
                f"Chưa phân loại: {s.pending_count} | Chi tháng: {_fmt(s.monthly_expense)} | "
                f"Thu tháng: {_fmt(s.monthly_income)}"
            )
            print(f"Chi theo tag: {s.expense_by_tag}")
            print(f"Lịch nhắc chốt số dư kế tiếp: {s.next_reconciliation_reminder}")

        else:
            print("Lệnh không hợp lệ.")


if __name__ == "__main__":
    main()
