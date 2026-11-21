"""Offline tag recommender powered by merchant normalization, personal history,
and Vietnamese cold-start keyword rules (1-to-1 parity with Swift TagSuggester)."""

from __future__ import annotations

import re
import unicodedata
from typing import Dict, List

from core.models import Direction, Tag, Transaction, TransactionStatus

_NOISE_TOKENS: frozenset[str] = frozenset(
    {
        "chuyen", "tien", "khoan", "thanh", "toan", "dich", "vu", "giao", "ngan",
        "hang", "cho", "ban", "tu", "den", "qua", "tai", "vao", "vi", "momo",
        "mbbank", "vietqr", "nhanh", "trace", "nd", "gd", "sd", "vnd", "khong",
        "ro", "noi", "dung", "don", "nhap", "tay",
    }
)

_EXPENSE_RULES: tuple[tuple[str, tuple[str, ...]], ...] = (
    (
        "tag_cf",
        (
            "highlands", "phuc long", "starbucks", "katinat", "the coffee house",
            "cong ca phe", "tra sua", "gong cha", "koi", "tocotoco", "mixue",
            "phe la", "cafe", "ca phe", "coffee", "cf",
        ),
    ),
    (
        "tag_an_uong",
        (
            "grabfood", "shopeefood", "befood", "com", "pho", "bun", "banh mi",
            "lau", "nuong", "an trua", "an toi", "an sang", "pizza", "kfc",
            "lotteria", "mcdonald", "jollibee", "circle k", "gs25", "ministop",
            "winmart", "bach hoa xanh", "coopmart", "aeon", "sieu thi", "nha hang",
        ),
    ),
    (
        "tag_di_chuyen",
        (
            "grab", "xanh sm", "gsm", "be ", "xang", "petrolimex", "pvoil",
            "gui xe", "ve xe", "ve may bay", "vietjet", "vietnam airlines",
            "bamboo", "metro", "taxi", "xe om", "thu phi", "vetc", "epass",
        ),
    ),
    (
        "tag_mua_sam",
        (
            "shopee", "lazada", "tiki", "tiktok shop", "uniqlo", "zara", "hasaki",
            "guardian", "mua sam", "the gioi di dong", "cellphones", "fpt shop",
            "dien may xanh", "con cung", "decathlon",
        ),
    ),
    (
        "tag_hoa_don",
        (
            "apple services", "icloud", "app store", "google", "evn", "tien dien",
            "tien nuoc", "internet", "fpt telecom", "viettel", "vnpt", "mobifone",
            "vinaphone", "dien thoai", "nha tro", "tien nha", "phi quan ly", "hoa don",
        ),
    ),
    (
        "tag_giai_tri",
        (
            "cgv", "lotte cinema", "galaxy", "beta", "spotify", "netflix",
            "youtube", "steam", "game", "bida", "karaoke", "du lich", "khach san",
            "agoda", "booking", "traveloka",
        ),
    ),
    (
        "tag_tra_no",
        ("tra no", "gui lai", "tra tien", "vay", "muon", "hoan lai"),
    ),
)

_INCOME_RULES: tuple[tuple[str, tuple[str, ...]], ...] = (
    (
        "tag_hoan_tien",
        ("hoan tien", "duoc hoan", "refund", "tra no", "chia tien", "campuchia"),
    ),
    (
        "tag_thu_nhap",
        (
            "luong", "salary", "thuong", "bonus", "tien loi", "tui than tai",
            "lai suat", "co tuc", "thu nhap",
        ),
    ),
)


def _strip_lower_ascii(text: str) -> str:
    replaced = text.replace("đ", "d").replace("Đ", "D")
    decomposed = unicodedata.normalize("NFD", replaced)
    return "".join(ch for ch in decomposed if unicodedata.category(ch) != "Mn").lower()


def normalize_merchant_key(text: str) -> str:
    stripped = _strip_lower_ascii(text)
    tokens = [
        tok
        for tok in re.split(r"[^a-z0-9]+", stripped)
        if len(tok) >= 2 and not tok.isdigit() and tok not in _NOISE_TOKENS
    ]
    return " ".join(tokens)


def suggest_tags(
    tx: Transaction,
    history: List[Transaction],
    available_tags: List[Tag],
    limit: int = 3,
) -> List[Tag]:
    if limit <= 0 or not available_tags:
        return []

    tags_by_id: Dict[str, Tag] = {t.id: t for t in available_tags}
    target_key = normalize_merchant_key(f"{tx.description} {tx.note}")
    target_tokens = {tok for tok in target_key.split() if len(tok) >= 3}
    raw_normalized = _strip_lower_ascii(f"{tx.description} {tx.note}")

    scores: Dict[str, int] = {}
    direction_freq: Dict[str, int] = {}

    for past in history:
        if (
            past.id == tx.id
            or past.status != TransactionStatus.CONFIRMED
            or past.direction != tx.direction
            or not past.tag_id
            or past.tag_id not in tags_by_id
        ):
            continue

        direction_freq[past.tag_id] = direction_freq.get(past.tag_id, 0) + 1
        if not target_key:
            continue

        past_key = normalize_merchant_key(f"{past.description} {past.note}")
        if not past_key:
            continue

        if past_key == target_key:
            scores[past.tag_id] = scores.get(past.tag_id, 0) + 120
        elif past_key in target_key or target_key in past_key:
            scores[past.tag_id] = scores.get(past.tag_id, 0) + 70
        else:
            past_tokens = {tok for tok in past_key.split() if len(tok) >= 3}
            overlap = len(target_tokens & past_tokens)
            if overlap > 0:
                scores[past.tag_id] = scores.get(past.tag_id, 0) + overlap * 35

    rules = _EXPENSE_RULES if tx.direction == Direction.OUT else _INCOME_RULES
    for tag_id, keywords in rules:
        if tag_id not in tags_by_id:
            continue
        if any(kw in raw_normalized for kw in keywords):
            scores[tag_id] = scores.get(tag_id, 0) + 50

    ordered_ids = [
        tag_id
        for tag_id, _ in sorted(
            scores.items(),
            key=lambda kv: (
                -kv[1],
                -direction_freq.get(kv[0], 0),
                tags_by_id[kv[0]].sort_order,
            ),
        )
    ]

    for tag_id, _ in sorted(direction_freq.items(), key=lambda kv: -kv[1]):
        if tag_id not in ordered_ids:
            ordered_ids.append(tag_id)

    defaults = (
        ("tag_an_uong", "tag_cf", "tag_mua_sam", "tag_di_chuyen", "tag_hoa_don")
        if tx.direction == Direction.OUT
        else ("tag_thu_nhap", "tag_hoan_tien", "tag_tra_no")
    )
    for tag_id in defaults:
        if tag_id in tags_by_id and tag_id not in ordered_ids:
            ordered_ids.append(tag_id)

    for tag in available_tags:
        if tag.id not in ordered_ids:
            ordered_ids.append(tag.id)

    return [tags_by_id[tag_id] for tag_id in ordered_ids[:limit]]
