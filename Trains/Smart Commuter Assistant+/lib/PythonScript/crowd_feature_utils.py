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
    "KJ": 15.0,
    "AG": 13.0,
    "PH": 13.0,
    "MRT": 16.0,
    "PYL": 15.0,
    "MR": 12.0,
    "BRT": 9.0,
}

HEADWAY_RANGES = {
    "KJ": {"crush": (3, 4), "peak": (4, 6), "offpeak": (7, 10), "late": (10, 18)},
    "AG": {"crush": (4, 5), "peak": (4, 7), "offpeak": (7, 12), "late": (10, 18)},
    "PH": {"crush": (4, 5), "peak": (4, 7), "offpeak": (7, 12), "late": (10, 18)},
    "MRT": {"crush": (3, 4), "peak": (4, 6), "offpeak": (7, 10), "late": (10, 16)},
    "PYL": {"crush": (4, 5), "peak": (4, 7), "offpeak": (7, 11), "late": (10, 16)},
    "MR": {"crush": (5, 6), "peak": (5, 8), "offpeak": (8, 12), "late": (10, 18)},
    "BRT": {"crush": (6, 8), "peak": (6, 9), "offpeak": (8, 13), "late": (10, 18)},
}

# Encodes the Klang Valley station tiers described by the user:
# 4 = major interchange bottleneck
# 3 = CBD / commercial hub
# 2 = dense commuter / university / gateway node
STATION_PRESSURE_KEYWORDS = {
    4: (
        "KL SENTRAL",
        "PASAR SENI",
        "MASJID JAMEK",
        "TITIWANGSA",
        "HANG TUAH",
        "TUN RAZAK EXCHANGE",
        "TRX",
    ),
    3: (
        "BUKIT BINTANG",
        "KLCC",
        "PERSIARAN KLCC",
        "BANDAR UTAMA",
        "ABDULLAH HUKUM",
        "MID VALLEY",
    ),
    2: (
        "WANGSA MAJU",
        "SS 15",
        "SS15",
        "BANDAR TASIK SELATAN",
        "TBS",
        "BUKIT JALIL",
        "STADIUM KAJANG",
    ),
}

EVENT_HOTSPOT_KEYWORDS = {
    3: ("BUKIT JALIL", "STADIUM KAJANG"),
    2: (
        "BUKIT BINTANG",
        "KLCC",
        "PERSIARAN KLCC",
        "BANDAR UTAMA",
        "ABDULLAH HUKUM",
        "MID VALLEY",
    ),
    1: (
        "KL SENTRAL",
        "PASAR SENI",
        "MASJID JAMEK",
        "TITIWANGSA",
        "HANG TUAH",
        "TUN RAZAK EXCHANGE",
        "TRX",
    ),
}


@dataclass(frozen=True)
class StopMetadata:
    stop_id: str
    stop_name: str
    route_id: str
    is_interchange: bool


@dataclass(frozen=True)
class StationCrowdProfile:
    pressure_score: int
    event_score: int


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


def _normalize_station_name(value: str) -> str:
    uppercase = value.upper()
    cleaned = "".join(ch if ch.isalnum() else " " for ch in uppercase)
    return " ".join(cleaned.split())


def _compact_station_name(value: str) -> str:
    return _normalize_station_name(value).replace(" ", "")


def _matches_station_alias(stop_name: str, alias: str) -> bool:
    normalized_stop = _normalize_station_name(stop_name)
    normalized_alias = _normalize_station_name(alias)
    if normalized_alias in normalized_stop:
        return True
    return _compact_station_name(alias) in _compact_station_name(stop_name)


def event_hotspot_score(stop_name: str) -> int:
    score = 0
    for weight, aliases in EVENT_HOTSPOT_KEYWORDS.items():
        for alias in aliases:
            if _matches_station_alias(stop_name, alias):
                score = max(score, weight)
                break
    return score


def station_profile(stop: StopMetadata) -> StationCrowdProfile:
    pressure_score = 0
    for weight, aliases in STATION_PRESSURE_KEYWORDS.items():
        for alias in aliases:
            if _matches_station_alias(stop.stop_name, alias):
                pressure_score = max(pressure_score, weight)
                break

    if stop.is_interchange:
        pressure_score = max(pressure_score, 1)

    return StationCrowdProfile(
        pressure_score=pressure_score,
        event_score=event_hotspot_score(stop.stop_name),
    )


def station_pressure_score(stop: StopMetadata) -> int:
    return station_profile(stop).pressure_score


def peak_period_score(
    when: datetime,
    is_weekend: int | None = None,
) -> int:
    weekend = (1 if when.weekday() >= 5 else 0) if is_weekend is None else int(is_weekend)
    minutes = (when.hour * 60) + when.minute

    if weekend == 1:
        if 10 * 60 <= minutes < 22 * 60:
            return 1
        return 0

    if (7 * 60 + 30 <= minutes < 8 * 60 + 30) or (
        17 * 60 + 30 <= minutes < 18 * 60 + 30
    ):
        return 3
    if (6 * 60 + 30 <= minutes < 9 * 60 + 30) or (
        16 * 60 + 30 <= minutes < 19 * 60 + 30
    ):
        return 2
    if (6 * 60 <= minutes < 6 * 60 + 30) or (
        16 * 60 <= minutes < 16 * 60 + 30
    ):
        return 1
    return 0


def infer_event_intensity(
    stop: StopMetadata,
    hour: int,
    is_weekend: int,
    minute: int = 0,
    rng: random.Random | None = None,
    global_event_level: float = 0.0,
) -> int:
    profile = station_profile(stop)
    minutes = (hour * 60) + minute
    evening_window = 16 * 60 + 30 <= minutes < 22 * 60
    weekend_window = is_weekend == 1 and 10 * 60 <= minutes < 22 * 60

    base = 0
    if profile.event_score >= 3:
        if global_event_level > 0 and (weekend_window or evening_window):
            base = 1
    elif profile.event_score == 2:
        if weekend_window:
            base = 2
        elif evening_window:
            base = 1
    elif profile.event_score == 1 and (weekend_window or evening_window):
        base = 1

    if profile.pressure_score >= 4 and weekend_window:
        base = max(base, 1)

    global_lift = global_event_level * (1.6 if profile.event_score >= 3 else 1.0)
    if rng is None:
        jitter_seed = sum(ord(ch) for ch in stop.stop_id.upper()) + (hour * 13) + minute
        jitter = 1 if jitter_seed % 17 == 0 else 0
    else:
        threshold = 0.86 if profile.event_score >= 3 else 0.93
        jitter = 1 if rng.random() > threshold else 0

    level = int(round(base + global_lift + jitter))
    return max(0, min(3, level))


def base_route_pressure(route_id: str) -> float:
    return ROUTE_PRESSURE.get(route_id, 10.0)


def sample_headway_minutes(
    route_id: str,
    when: datetime,
    is_weekend: int,
    rng: random.Random | None = None,
) -> int:
    peak_score = peak_period_score(when, is_weekend=is_weekend)
    minutes = (when.hour * 60) + when.minute

    if peak_score >= 3:
        bucket = "crush"
    elif peak_score >= 2:
        bucket = "peak"
    elif (is_weekend == 1 and 10 * 60 <= minutes < 22 * 60) or (
        6 * 60 <= minutes < 20 * 60
    ):
        bucket = "offpeak"
    else:
        bucket = "late"

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
    profile = station_profile(stop)
    peak_period = peak_period_score(when, is_weekend=is_weekend)
    return {
        "stop_id": stop.stop_id,
        "route_id": stop.route_id,
        "hour": when.hour,
        "is_weekend": is_weekend,
        "is_raining": int(is_raining),
        "is_holiday": is_holiday_date(when.date(), extra_holidays),
        "peak_period": peak_period,
        "station_pressure": profile.pressure_score,
        "event_intensity": infer_event_intensity(
            stop,
            hour=when.hour,
            minute=when.minute,
            is_weekend=is_weekend,
            rng=rng,
            global_event_level=global_event_level,
        ),
        "headway_minutes": sample_headway_minutes(
            stop.route_id,
            when=when,
            is_weekend=is_weekend,
            rng=rng,
        ),
    }


def estimate_occupancy_percent(
    stop: StopMetadata,
    features: dict[str, object],
    rng: random.Random | None = None,
    trend_strength: float = 0.0,
) -> float:
    peak_period = int(features.get("peak_period", 0))
    station_pressure = int(features.get("station_pressure", station_pressure_score(stop)))
    is_weekend = int(features.get("is_weekend", 0))
    is_raining = int(features.get("is_raining", 0))
    is_holiday = int(features.get("is_holiday", 0))
    event_intensity = int(features.get("event_intensity", 0))
    headway_minutes = int(features.get("headway_minutes", 6))
    hour = int(features.get("hour", 12))

    profile = station_profile(stop)
    clamped_trend = min(max(float(trend_strength), 0.0), 1.0)

    peak_adjust = {0: 0.0, 1: 8.0, 2: 22.0, 3: 34.0}.get(peak_period, 0.0)
    if is_weekend == 1 and profile.pressure_score >= 3 and 10 <= hour <= 21:
        peak_adjust = max(peak_adjust, 10.0)

    commute_bonus = 0.0
    if is_weekend == 0:
        if peak_period >= 3:
            commute_bonus = station_pressure * 3.0
        elif peak_period == 2:
            commute_bonus = station_pressure * 2.0
        elif peak_period == 1:
            commute_bonus = station_pressure * 1.0
    elif profile.pressure_score >= 3 and 12 <= hour <= 20:
        commute_bonus = 3.0

    event_weight = 12.0 if profile.event_score >= 3 else 9.0
    noise = rng.uniform(-5.0, 5.0) if rng is not None else 0.0

    occupancy_percent = (
        10.0
        + base_route_pressure(stop.route_id)
        + (clamped_trend * 24.0)
        + peak_adjust
        + (-8.0 if is_weekend else 4.0)
        + (6.0 if is_holiday else 0.0)
        + (6.0 if is_raining else 0.0)
        + (event_intensity * event_weight)
        + (max(headway_minutes - 4, 0) * 1.8)
        + (station_pressure * 6.0)
        + (4.0 if stop.is_interchange and station_pressure < 4 else 0.0)
        + commute_bonus
        + (stop_bias(stop.stop_id) * 1.2)
        + noise
    )
    return max(0.0, min(100.0, occupancy_percent))
