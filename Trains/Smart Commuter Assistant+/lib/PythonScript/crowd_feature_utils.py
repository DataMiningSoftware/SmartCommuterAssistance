from __future__ import annotations

from dataclasses import dataclass
from datetime import date, datetime
import os
import random
from pathlib import Path

import pandas as pd


FIXED_HOLIDAYS = {
    (1, 1),   # New Year
    (5, 1),   # Labour Day
    (8, 31),  # Merdeka
    (9, 16),  # Malaysia Day
    (12, 25), # Christmas
}

ROUTE_PRESSURE = {
    "KJ": 14.0,
    "AG": 12.0,
    "PH": 12.0,
    "MRT": 16.0,
    "PYL": 15.0,
    "MR": 11.0,
    "BRT": 9.0,
}

HEADWAY_RANGES = {
    "KJ": {"peak": (3, 5), "shoulder": (5, 7), "late": (7, 10)},
    "AG": {"peak": (4, 6), "shoulder": (5, 8), "late": (8, 12)},
    "PH": {"peak": (4, 6), "shoulder": (5, 8), "late": (8, 12)},
    "MRT": {"peak": (3, 5), "shoulder": (5, 7), "late": (7, 10)},
    "PYL": {"peak": (4, 6), "shoulder": (5, 8), "late": (8, 11)},
    "MR": {"peak": (5, 7), "shoulder": (6, 9), "late": (8, 12)},
    "BRT": {"peak": (5, 8), "shoulder": (7, 10), "late": (9, 12)},
}

EVENT_KEYWORDS = {
    "BUKIT BINTANG": 2,
    "KLCC": 2,
    "MERDEKA": 2,
    "PASAR SENI": 2,
    "SENTRAL": 2,
    "STADIUM": 2,
    "TRX": 2,
    "TUN RAZAK EXCHANGE": 2,
    "HANG TUAH": 1,
    "MASJID JAMEK": 1,
    "TITIWANGSA": 1,
}


@dataclass(frozen=True)
class StopMetadata:
    stop_id: str
    stop_name: str
    route_id: str
    is_interchange: bool


def normalize_route_id(raw_route: str, stop_id: str) -> str:
    route = (raw_route or "").strip().upper()
    if not route:
        route = "".join(ch for ch in stop_id.upper() if ch.isalpha())
    if route.startswith("KG") or route == "MRT":
        return "MRT"
    if route.startswith("PY"):
        return "PYL"
    if route.startswith("SP") or route.startswith("PH"):
        return "PH"
    if route.startswith("AG"):
        return "AG"
    if route.startswith("KJ"):
        return "KJ"
    if route.startswith("MR"):
        return "MR"
    if route.startswith("BRT"):
        return "BRT"
    return route[:3] if route else "KJ"


def load_stop_metadata(stops_csv: Path) -> dict[str, StopMetadata]:
    df = pd.read_csv(stops_csv)
    if "stop_id" not in df.columns or "stop_name" not in df.columns:
        raise ValueError(f"Missing stop metadata columns in {stops_csv}")

    metadata: dict[str, StopMetadata] = {}
    for _, row in df.iterrows():
        stop_id = str(row.get("stop_id", "")).strip().upper()
        stop_name = str(row.get("stop_name", "")).strip()
        if not stop_id or not stop_name:
            continue
        route_id = normalize_route_id(str(row.get("route_id", "")), stop_id)
        interchange_raw = str(row.get("is_interchange", "")).strip().lower()
        is_interchange = interchange_raw in {"true", "1", "yes"}
        metadata[stop_id] = StopMetadata(
            stop_id=stop_id,
            stop_name=stop_name,
            route_id=route_id,
            is_interchange=is_interchange,
        )
    return metadata


def parse_extra_holiday_dates(raw_value: str | None = None) -> set[date]:
    raw = (raw_value or os.getenv("HOLIDAY_DATES", "")).strip()
    if not raw:
        return set()

    parsed: set[date] = set()
    for token in raw.split(","):
        value = token.strip()
        if not value:
            continue
        parsed_date = date.fromisoformat(value)
        parsed.add(parsed_date)
    return parsed


def is_holiday_date(target: date, extra_dates: set[date] | None = None) -> int:
    if extra_dates and target in extra_dates:
        return 1
    return 1 if (target.month, target.day) in FIXED_HOLIDAYS else 0


def stop_bias(stop_id: str) -> float:
    checksum = sum(ord(ch) for ch in stop_id.upper())
    return float((checksum % 11) - 5)


def event_hotspot_score(stop_name: str) -> int:
    upper_name = stop_name.upper()
    score = 0
    for keyword, weight in EVENT_KEYWORDS.items():
        if keyword in upper_name:
            score = max(score, weight)
    return score


def infer_event_intensity(
    stop: StopMetadata,
    hour: int,
    is_weekend: int,
    rng: random.Random | None = None,
    global_event_level: float = 0.0,
) -> int:
    hotspot = event_hotspot_score(stop.stop_name)
    evening_window = 17 <= hour <= 22
    weekend_window = is_weekend == 1 and 10 <= hour <= 22

    base = 0
    if weekend_window:
        base = hotspot
    elif evening_window:
        base = max(hotspot - 1, 0)

    if stop.is_interchange and (weekend_window or evening_window):
        base = max(base, 1)

    if rng is None:
        jitter = (sum(ord(ch) for ch in stop.stop_id) + hour + is_weekend) % 2
    else:
        jitter = 1 if rng.random() > 0.7 else 0

    level = int(round(base + global_event_level + jitter))
    return max(0, min(3, level))


def base_route_pressure(route_id: str) -> float:
    return ROUTE_PRESSURE.get(route_id, 10.0)


def sample_headway_minutes(
    route_id: str,
    hour: int,
    is_weekend: int,
    rng: random.Random | None = None,
) -> int:
    if is_weekend == 0 and ((7 <= hour <= 9) or (17 <= hour <= 19)):
        bucket = "peak"
    elif hour <= 5 or hour >= 22:
        bucket = "late"
    else:
        bucket = "shoulder"

    route_ranges = HEADWAY_RANGES.get(route_id, HEADWAY_RANGES["KJ"])
    low, high = route_ranges[bucket]
    if rng is None:
        return int(round((low + high) / 2))
    return rng.randint(low, high)


def build_feature_row(
    stop: StopMetadata,
    when: datetime,
    is_raining: int,
    rng: random.Random | None = None,
    global_event_level: float = 0.0,
    extra_holidays: set[date] | None = None,
) -> dict[str, object]:
    is_weekend = 1 if when.weekday() >= 5 else 0
    return {
        "stop_id": stop.stop_id,
        "route_id": stop.route_id,
        "hour": when.hour,
        "is_weekend": is_weekend,
        "is_raining": int(is_raining),
        "is_holiday": is_holiday_date(when.date(), extra_holidays),
        "event_intensity": infer_event_intensity(
            stop,
            hour=when.hour,
            is_weekend=is_weekend,
            rng=rng,
            global_event_level=global_event_level,
        ),
        "headway_minutes": sample_headway_minutes(
            stop.route_id,
            hour=when.hour,
            is_weekend=is_weekend,
            rng=rng,
        ),
    }
