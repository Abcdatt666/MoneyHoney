"""Notification parser for MBBank and MoMo push notifications."""

from __future__ import annotations

import re
import unicodedata
from dataclasses import dataclass
from datetime import datetime
from typing import Optional

from core.models import Direction, RawNotification, TransactionType, WalletId


@dataclass(frozen=True)
class ParsedTransaction:
    """Structured output produced from a raw bank or wallet notification."""

    tx_type: TransactionType
    source_wallet_id: WalletId
    target_wallet_id: Optional[WalletId]
    amount: int
    direction: Direction
    description: str
    trace_id: Optional[str]
    reported_balance_after: Optional[int]
    occurred_at: datetime


# Real MBBank segment patterns:
# TK 0901234567|GD: +500,000VND 20/11/26 15:45|SD: 12,500,000VND| ND: NGUYEN VAN A chuyen tien - Ma giao dich/ Trace 123456
_MB_GD_RE = re.compile(
    r"GD\s*:\s*(?P<sign>[+-])\s*(?P<num>\d{1,3}(?:[.,]\d{3})+|\d+)\s*(?:VND|VNĐ|Đ|D)?"
    r"(?:\s+(?P<dt>\d{2}/\d{2}/\d{2,4}\s+\d{2}:\d{2}(?::\d{2})?))?",
    re.IGNORECASE,
)

_SIGNED_AMOUNT_RE = re.compile(
    r"(?P<sign>[+-])\s*(?P<num>\d{1,3}(?:[.,]\d{3})+|\d+)\s*(?:VND|VNĐ|Đ|D)?",
    re.IGNORECASE,
)

_CURRENCY_AMOUNT_RE = re.compile(
    r"\b(?P<num>\d{1,3}(?:[.,]\d{3})+|\d+)\s*(?:VND|VNĐ|đ)\b",
    re.IGNORECASE,
)

_BALANCE_RE = re.compile(
    r"(?:SD|SO\s*DU|SỐ\s*DƯ)\s*[:\-]?\s*(?P<num>\d{1,3}(?:[.,]\d{3})+|\d+)\s*(?:VND|VNĐ|Đ|D)?",
    re.IGNORECASE,
)

_ND_RE = re.compile(r"(?:ND|NỘI\s*DUNG|NOI\s*DUNG)\s*:\s*(?P<val>[^|\n]+)", re.IGNORECASE)

_TRACE_RE = re.compile(
    r"(?:-\s*)?(?:M[aã]\s+giao\s+d[iị]ch\s*/\s*Trace|Trace)\s*[:#]?\s*(?P<trace>[A-Z0-9]+)\b",
    re.IGNORECASE,
)

_MOMO_RECEIVE_RE = re.compile(
    r"^(?P<sender>.+?)\s+(?:đã\s+)?(?:chuyển|gửi)\s+(?:tiền\s+)?(?:cho\s+bạn|đến\s+bạn)",
    re.IGNORECASE,
)

_PROMO_KEYWORDS: tuple[str, ...] = (
    "UU DAI",
    "KHUYEN MAI",
    "GIAM GIA",
    "VOUCHER",
    "HOAN TIEN LEN DEN",
    "BAO TRI",
    "CAP NHAT UNG DUNG",
    "MA OTP",
    "OTP",
)

_IN_PHRASES: tuple[str, ...] = (
    "NHAN DUOC",
    "NHAN TIEN",
    "CHUYEN CHO BAN",
    "GUI CHO BAN",
    "CHUYEN DEN BAN",
    "CONG TIEN",
    "HOAN TIEN",
)

_OUT_PHRASES: tuple[str, ...] = (
    "THANH TOAN",
    "CHUYEN TIEN",
    "CHUYEN KHOAN",
    "DA CHUYEN",
    "TRU TIEN",
    "RUT TIEN",
)


def _strip_vietnamese_accents(text: str) -> str:
    replaced = text.replace("đ", "d").replace("Đ", "D")
    decomposed = unicodedata.normalize("NFD", replaced)
    return "".join(ch for ch in decomposed if unicodedata.category(ch) != "Mn")


def _parse_vnd_int(num_text: str) -> int:
    return int(re.sub(r"[.,\s]", "", num_text))


def _parse_mb_datetime(dt_text: Optional[str], fallback: datetime) -> datetime:
    if not dt_text:
        return fallback
    for fmt in ("%d/%m/%y %H:%M", "%d/%m/%Y %H:%M", "%d/%m/%y %H:%M:%S", "%d/%m/%Y %H:%M:%S"):
        try:
            return datetime.strptime(dt_text.strip(), fmt)
        except ValueError:
            continue
    return fallback


def _extract_amount_direction_and_time(
    text: str, fallback_dt: datetime
) -> Optional[tuple[int, Direction, datetime]]:
    mb_gd = _MB_GD_RE.search(text)
    if mb_gd:
        amount = _parse_vnd_int(mb_gd.group("num"))
        if amount <= 0:
            return None
        direction = Direction.OUT if mb_gd.group("sign") == "-" else Direction.IN
        occurred_at = _parse_mb_datetime(mb_gd.group("dt"), fallback_dt)
        return amount, direction, occurred_at

    # Strip SD: segment before searching generic amounts.
    text_no_sd = _BALANCE_RE.sub(" ", text)

    signed_match = _SIGNED_AMOUNT_RE.search(text_no_sd)
    if signed_match:
        amount = _parse_vnd_int(signed_match.group("num"))
        if amount <= 0:
            return None
        direction = Direction.OUT if signed_match.group("sign") == "-" else Direction.IN
        return amount, direction, fallback_dt

    upper_ascii = _strip_vietnamese_accents(text_no_sd).upper()
    currency_match = _CURRENCY_AMOUNT_RE.search(text_no_sd)
    if not currency_match:
        return None

    amount = _parse_vnd_int(currency_match.group("num"))
    if amount <= 0:
        return None

    if any(phrase in upper_ascii for phrase in _IN_PHRASES):
        return amount, Direction.IN, fallback_dt
    if any(phrase in upper_ascii for phrase in _OUT_PHRASES):
        return amount, Direction.OUT, fallback_dt

    return None


def _extract_reported_balance(text: str) -> Optional[int]:
    match = _BALANCE_RE.search(text)
    if not match:
        return None
    return _parse_vnd_int(match.group("num"))


def _extract_trace_id(text: str) -> Optional[str]:
    match = _TRACE_RE.search(text)
    return match.group("trace").strip() if match else None


def _extract_description(raw_title: str, raw_body: str) -> str:
    combined = f"{raw_title}\n{raw_body}".strip()
    upper_ascii = _strip_vietnamese_accents(combined).upper()

    if "MOMO-CASHIN" in upper_ascii:
        return "MOMO-CASHIN"
    if "MOMO-CASHOUT" in upper_ascii:
        return "MOMO-CASHOUT"

    nd_match = _ND_RE.search(combined)
    if nd_match:
        desc = _TRACE_RE.sub("", nd_match.group("val")).strip(" .:-|")
        if desc:
            return desc

    momo_match = _MOMO_RECEIVE_RE.search(raw_body.strip())
    if momo_match:
        sender = momo_match.group("sender").strip(" .:-")
        msg_match = re.search(r"L[ơờ]i\s+nh[ắa]n\s*:\s*(?P<msg>.+)$", raw_body, re.IGNORECASE)
        if msg_match:
            return f"{sender} - {msg_match.group('msg').strip()}"
        return sender

    cleaned = _BALANCE_RE.sub(" ", raw_body)
    cleaned = _TRACE_RE.sub(" ", cleaned)
    cleaned = _SIGNED_AMOUNT_RE.sub(" ", cleaned)
    cleaned = _CURRENCY_AMOUNT_RE.sub(" ", cleaned)
    cleaned = re.sub(r"\s+", " ", cleaned).strip(" .:-|")
    return cleaned if cleaned else "Không rõ nội dung"


def parse_notification(raw: RawNotification) -> Optional[ParsedTransaction]:
    """Parse an MBBank or MoMo push notification into a structured transaction.

    Returns None when the notification is promotional, OTP, or not a valid
    monetary transaction.
    """
    combined = f"{raw.title} {raw.body}".strip()
    if not combined:
        return None

    upper_ascii = _strip_vietnamese_accents(combined).upper()
    if any(promo in upper_ascii for promo in _PROMO_KEYWORDS) and not _SIGNED_AMOUNT_RE.search(
        _BALANCE_RE.sub(" ", combined)
    ):
        return None

    extracted = _extract_amount_direction_and_time(combined, raw.received_at)
    if extracted is None:
        return None

    amount, direction, occurred_at = extracted
    reported_balance = _extract_reported_balance(combined)
    trace_id = _extract_trace_id(combined)
    description = _extract_description(raw.title, raw.body)

    if raw.source_app == WalletId.MBBANK:
        if "MOMO-CASHIN" in upper_ascii and direction == Direction.OUT:
            return ParsedTransaction(
                tx_type=TransactionType.INTERNAL_TRANSFER,
                source_wallet_id=WalletId.MBBANK,
                target_wallet_id=WalletId.MOMO,
                amount=amount,
                direction=Direction.OUT,
                description="Nạp tiền ví MoMo (MOMO-CASHIN)",
                trace_id=trace_id,
                reported_balance_after=reported_balance,
                occurred_at=occurred_at,
            )
        if "MOMO-CASHOUT" in upper_ascii and direction == Direction.IN:
            return ParsedTransaction(
                tx_type=TransactionType.INTERNAL_TRANSFER,
                source_wallet_id=WalletId.MOMO,
                target_wallet_id=WalletId.MBBANK,
                amount=amount,
                direction=Direction.IN,
                description="Rút tiền từ MoMo về MBBank (MOMO-CASHOUT)",
                trace_id=trace_id,
                reported_balance_after=reported_balance,
                occurred_at=occurred_at,
            )

    tx_type = (
        TransactionType.EXPENSE if direction == Direction.OUT else TransactionType.INCOME
    )

    return ParsedTransaction(
        tx_type=tx_type,
        source_wallet_id=raw.source_app,
        target_wallet_id=None,
        amount=amount,
        direction=direction,
        description=description,
        trace_id=trace_id,
        reported_balance_after=reported_balance,
        occurred_at=occurred_at,
    )
