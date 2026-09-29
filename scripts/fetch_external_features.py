from __future__ import annotations

import argparse
import csv
import json
import urllib.request
from collections import defaultdict
from datetime import date, datetime, timedelta
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
CACHE_PATH = SCRIPT_DIR / "external_features_cache.csv"
HOLIDAYS_PATH = SCRIPT_DIR / "holidays_my.json"
EVENTS_PATH = SCRIPT_DIR / "events_my.json"

RIDERSHIP_URL = (
    "https://api.data.gov.my/data-catalogue?id=ridership_headline&limit=5000"
)
RAIN_URL = (
    "https://api.open-meteo.com/v1/forecast"
    "?latitude=3.1390&longitude=101.6869"
    "&hourly=precipitation&past_days=92&forecast_days=1"
    "&timezone=Asia%2FKuala_Lumpur"
)

LINE_RIDERSHIP_FIELD = {
    "KJ": "rail_lrt_kj",
    "MRT": "rail_mrt_kajang",
    "PYL": "rail_mrt_pjy",
    "AG": "rail_lrt_ampang",
    "PH": "rail_lrt_ampang",
    "MR": "rail_monorail",
    "KT1": "rail_komuter",
    "KT2": "rail_komuter",
}
EXTRA_LINES = ["ER6", "ER7", "BRT"]
ALL_LINES = list(LINE_RIDERSHIP_FIELD) + EXTRA_LINES


def fetch_json(url: str) -> object:
    request = urllib.request.Request(
        url,
        headers={"User-Agent": "SmartCommuterAssistant/1.0"},
    )
    with urllib.request.urlopen(request, timeout=60) as response:
        return json.loads(response.read().decode("utf-8"))


def daily_rain_mm() -> dict[str, float]:
    payload = fetch_json(RAIN_URL)
    hourly = payload.get("hourly", {}) if isinstance(payload, dict) else {}
    times = hourly.get("time", []) or []
    values = hourly.get("precipitation", []) or []
    totals: dict[str, float] = defaultdict(float)
    for timestamp, value in zip(times, values):
        if timestamp is None or value is None:
            continue
        totals[str(timestamp)[:10]] += float(value)
    return {day: round(total, 2) for day, total in totals.items()}


def load_holidays() -> set[str]:
    if not HOLIDAYS_PATH.exists():
        return set()
    data = json.loads(HOLIDAYS_PATH.read_text(encoding="utf-8"))
    dates = set(data.get("federal", []))
    for state_dates in (data.get("states") or {}).values():
        dates.update(state_dates)
    return {str(value)[:10] for value in dates}


def load_event_dates() -> set[str]:
    if not EVENTS_PATH.exists():
        return set()
    data = json.loads(EVENTS_PATH.read_text(encoding="utf-8"))
    dates = set()
    for entry in data.get("events", []) or []:
        day = str(entry.get("date", ""))[:10]
        intensity = entry.get("intensity", 0)
        if day and isinstance(intensity, (int, float)) and intensity >= 1:
            dates.add(day)
    return dates


def compute_ridership_ratio(
    history: list[tuple[str, float]],
    target_index: int,
) -> float:
    target_date, target_value = history[target_index]
    if target_value <= 0:
        return 1.0
    target_dow = datetime.fromisoformat(target_date).weekday()
    prior = [
        value
        for day, value in history[:target_index]
        if datetime.fromisoformat(day).weekday() == target_dow and value > 0
    ][-4:]
    if not prior:
        return 1.0
    baseline = sum(prior) / len(prior)
    if baseline <= 0:
        return 1.0
    ratio = target_value / baseline
    return round(min(max(ratio, 0.5), 1.5), 4)


def build_rows(days: int) -> list[dict]:
    cutoff = (date.today() - timedelta(days=days)).isoformat()
    ridership_rows = fetch_json(RIDERSHIP_URL)

    history_by_line: dict[str, list[tuple[str, float]]] = defaultdict(list)
    for row in ridership_rows:
        if not isinstance(row, dict):
            continue
        day = str(row.get("date", ""))[:10]
        if day < cutoff:
            continue
        for line, field in LINE_RIDERSHIP_FIELD.items():
            value = row.get(field)
            if value is None:
                continue
            history_by_line[line].append((day, float(value)))
    for history in history_by_line.values():
        history.sort()

    rain = daily_rain_mm()
    holidays = load_holidays()
    events = load_event_dates()
    recent_days = sorted(day for day in rain if day >= cutoff)

    rows: list[dict] = []
    for line in ALL_LINES:
        history = history_by_line.get(line, [])
        for index, (day, value) in enumerate(history):
            rows.append(
                {
                    "date": day,
                    "line_id": line,
                    "ridership": int(value),
                    "ridership_ratio": compute_ridership_ratio(history, index),
                    "rain_mm": rain.get(day, 0.0),
                    "is_holiday": day in holidays,
                    "event_flag": day in events,
                }
            )
        if history:
            continue
        for day in recent_days:
            rows.append(
                {
                    "date": day,
                    "line_id": line,
                    "ridership": None,
                    "ridership_ratio": 1.0,
                    "rain_mm": rain.get(day, 0.0),
                    "is_holiday": day in holidays,
                    "event_flag": day in events,
                }
            )

    rows.sort(key=lambda item: (item["date"], item["line_id"]))
    return rows


def write_cache(rows: list[dict]) -> None:
    with CACHE_PATH.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.DictWriter(
            handle,
            fieldnames=[
                "date",
                "line_id",
                "ridership",
                "ridership_ratio",
                "rain_mm",
                "is_holiday",
                "event_flag",
            ],
        )
        writer.writeheader()
        writer.writerows(rows)


def upsert_supabase(rows: list[dict]) -> bool:
    import os

    url = os.getenv("SUPABASE_URL", "").strip()
    key = os.getenv("SUPABASE_SERVICE_KEY", "").strip()
    if not url or not key:
        print("  SUPABASE_URL / SUPABASE_SERVICE_KEY not set; skipped Supabase upsert")
        return False
    try:
        from supabase import create_client
    except ImportError:
        print("  supabase package not installed; skipped Supabase upsert")
        return False

    client = create_client(url, key)
    batch_size = 500
    try:
        for start in range(0, len(rows), batch_size):
            batch = rows[start : start + batch_size]
            client.table("external_daily_features").upsert(
                batch, on_conflict="date,line_id"
            ).execute()
        print(f"  Upserted {len(rows)} rows to external_daily_features")
        return True
    except Exception as error:
        print(f"  Supabase upsert failed (run migration_external_features.sql?): {error}")
        return False


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Fetch daily ridership, rainfall, holiday and event features."
    )
    parser.add_argument("--days", type=int, default=92)
    parser.add_argument("--write-supabase", action="store_true")
    args = parser.parse_args()

    rows = build_rows(args.days)
    write_cache(rows)
    print(f"Fetched {len(rows)} feature rows ({args.days} days) -> {CACHE_PATH.name}")

    if args.write_supabase:
        upsert_supabase(rows)


if __name__ == "__main__":
    main()
