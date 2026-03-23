from __future__ import annotations

import argparse
import os
from dataclasses import dataclass
from pathlib import Path

import pandas as pd
from supabase import Client, create_client


LINE_COLUMN_BY_ROUTE = {
    "KJ": "rail_lrt_kj",
    "AG": "rail_lrt_ampang",
    "PH": "rail_lrt_ampang",
    "SP": "rail_lrt_ampang",
    "MRT": "rail_mrt_kajang",
    "KG": "rail_mrt_kajang",
    "PYL": "rail_mrt_pjy",
    "PY": "rail_mrt_pjy",
    "MR": "rail_monorail",
    "BRT": "bus_rpn",
}

WEEKDAY_HOUR_PROFILE = [
    0.02,
    0.01,
    0.01,
    0.01,
    0.02,
    0.05,
    0.18,
    0.35,
    0.42,
    0.33,
    0.22,
    0.20,
    0.24,
    0.28,
    0.30,
    0.34,
    0.45,
    0.55,
    0.58,
    0.46,
    0.34,
    0.22,
    0.12,
    0.06,
]

WEEKEND_HOUR_PROFILE = [
    0.02,
    0.01,
    0.01,
    0.01,
    0.02,
    0.03,
    0.08,
    0.12,
    0.16,
    0.22,
    0.28,
    0.34,
    0.40,
    0.44,
    0.46,
    0.45,
    0.42,
    0.40,
    0.36,
    0.30,
    0.24,
    0.18,
    0.10,
    0.05,
]


@dataclass(frozen=True)
class StopMeta:
    stop_id: str
    route_id: str


def normalize_route_id(raw_route: str, stop_id: str) -> str:
    route = (raw_route or "").strip().upper()
    if not route:
        route = "".join(ch for ch in stop_id.upper() if ch.isalpha())
    if route.startswith("KG") or route == "MRT":
        return "MRT"
    if route.startswith("PY"):
        return "PYL"
    if route.startswith("SP") or route.startswith("PH"):
        return "AG"
    if route.startswith("AG"):
        return "AG"
    if route.startswith("KJ"):
        return "KJ"
    if route.startswith("MR"):
        return "MR"
    if route.startswith("BRT"):
        return "BRT"
    return route[:3] if route else "KJ"


def occupancy_level_from_percent(occupancy_percent: float) -> int:
    if occupancy_percent < 30:
        return 0
    if occupancy_percent < 60:
        return 1
    if occupancy_percent < 85:
        return 2
    return 3


def wait_minutes_from_level(level: int) -> int:
    return {0: 2, 1: 4, 2: 7, 3: 10}.get(level, 4)


def eta_multiplier_from_level(level: int, hour: int) -> float:
    base = {0: 1.00, 1: 1.08, 2: 1.18, 3: 1.30}.get(level, 1.10)
    if (7 <= hour <= 9) or (17 <= hour <= 19):
        base += 0.04
    return round(min(max(base, 1.00), 2.50), 2)


def stop_bias(stop_id: str) -> float:
    # Deterministic per-stop variation so all stations are not identical.
    checksum = sum(ord(ch) for ch in stop_id.upper())
    return float((checksum % 9) - 4)  # -4 .. +4


def load_stops(stops_csv: Path) -> list[StopMeta]:
    df = pd.read_csv(stops_csv)
    if "stop_id" not in df.columns:
        raise ValueError(f"Missing stop_id column in {stops_csv}")

    stops: list[StopMeta] = []
    for _, row in df.iterrows():
        stop_id = str(row.get("stop_id", "")).strip().upper()
        if not stop_id:
            continue
        route_id = normalize_route_id(str(row.get("route_id", "")), stop_id)
        stops.append(StopMeta(stop_id=stop_id, route_id=route_id))

    # Keep one entry per stop ID
    dedup: dict[str, StopMeta] = {}
    for stop in stops:
        dedup.setdefault(stop.stop_id, stop)
    return list(dedup.values())


def load_ridership(ridership_csv: Path) -> pd.DataFrame:
    df = pd.read_csv(ridership_csv, parse_dates=["date"])
    if "date" not in df.columns:
        raise ValueError(f"Missing date column in {ridership_csv}")

    for column in set(LINE_COLUMN_BY_ROUTE.values()):
        if column in df.columns:
            df[column] = pd.to_numeric(df[column], errors="coerce")
    df["is_weekend"] = df["date"].dt.dayofweek >= 5
    return df


def compute_line_strength(df: pd.DataFrame) -> dict[tuple[str, bool], float]:
    strengths: dict[tuple[str, bool], float] = {}
    fallback_values: list[float] = []

    for route, column in LINE_COLUMN_BY_ROUTE.items():
        if column not in df.columns:
            continue
        for is_weekend in [False, True]:
            scoped = df[df["is_weekend"] == is_weekend][column]
            mean_value = float(scoped.dropna().mean()) if not scoped.dropna().empty else 0.0
            strengths[(route, is_weekend)] = mean_value
            if mean_value > 0:
                fallback_values.append(mean_value)

    fallback_mean = float(sum(fallback_values) / len(fallback_values)) if fallback_values else 1.0
    for route in ["KJ", "AG", "MRT", "PYL", "MR", "BRT"]:
        for is_weekend in [False, True]:
            strengths.setdefault((route, is_weekend), fallback_mean)

    max_value = max(strengths.values()) if strengths else 1.0
    if max_value <= 0:
        max_value = 1.0

    normalized = {key: (value / max_value) for key, value in strengths.items()}
    return normalized


def hour_strength(hour: int, is_weekend: bool) -> float:
    profile = WEEKEND_HOUR_PROFILE if is_weekend else WEEKDAY_HOUR_PROFILE
    top = max(profile)
    return profile[hour] / top if top > 0 else 0.0


def build_forecast_rows(
    ridership_df: pd.DataFrame,
    stops: list[StopMeta],
) -> list[dict[str, object]]:
    line_strength = compute_line_strength(ridership_df)
    rows: list[dict[str, object]] = []

    for stop in stops:
        route = normalize_route_id(stop.route_id, stop.stop_id)
        for is_weekend in [False, True]:
            line_value = line_strength.get((route, is_weekend), 0.55)
            for hour in range(24):
                h_strength = hour_strength(hour, is_weekend)
                base = 12.0 + (line_value * 48.0) + (h_strength * 30.0)
                weekend_adjust = -8.0 if is_weekend else 4.0
                percent = base + weekend_adjust + stop_bias(stop.stop_id)
                percent = max(0.0, min(100.0, percent))

                level = occupancy_level_from_percent(percent)
                wait_minutes = wait_minutes_from_level(level)
                eta_multiplier = eta_multiplier_from_level(level, hour)

                rows.append(
                    {
                        "stop_id": stop.stop_id,
                        "forecast_hour": hour,
                        "is_weekend": is_weekend,
                        "occupancy_level": level,
                        "occupancy_percent": round(percent, 2),
                        "expected_wait_minutes": wait_minutes,
                        "eta_multiplier": eta_multiplier,
                        "source_type": "trend_model",
                    }
                )
    return rows


def chunked(items: list[dict[str, object]], chunk_size: int) -> list[list[dict[str, object]]]:
    return [items[i : i + chunk_size] for i in range(0, len(items), chunk_size)]


def upsert_rows(
    client: Client,
    table: str,
    rows: list[dict[str, object]],
    chunk_size: int,
) -> None:
    chunks = chunked(rows, chunk_size)
    for index, chunk in enumerate(chunks, start=1):
        client.table(table).upsert(
            chunk,
            on_conflict="stop_id,forecast_hour,is_weekend",
        ).execute()
        print(f"Upserted chunk {index}/{len(chunks)} ({len(chunk)} rows)")


def parse_args() -> argparse.Namespace:
    script_dir = Path(__file__).resolve().parent
    parser = argparse.ArgumentParser(
        description="Build hourly station crowd forecasts from ridership_headline.csv and upsert to Supabase."
    )
    parser.add_argument(
        "--ridership-csv",
        type=Path,
        required=True,
        help="Path to ridership_headline.csv",
    )
    parser.add_argument(
        "--stops-csv",
        type=Path,
        default=script_dir / "train_stops_kl.csv",
        help="Path to train_stops_kl.csv",
    )
    parser.add_argument(
        "--table",
        type=str,
        default="crowd_forecast_hourly",
        help="Target Supabase table",
    )
    parser.add_argument(
        "--chunk-size",
        type=int,
        default=1000,
        help="Rows per upsert request",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Generate rows and print sample only (no DB write).",
    )
    return parser.parse_args()


if __name__ == "__main__":
    args = parse_args()

    ridership_csv = args.ridership_csv
    stops_csv = args.stops_csv
    if not ridership_csv.exists():
        raise FileNotFoundError(f"ridership csv not found: {ridership_csv}")
    if not stops_csv.exists():
        raise FileNotFoundError(f"stops csv not found: {stops_csv}")

    ridership_df = load_ridership(ridership_csv)
    stops = load_stops(stops_csv)
    rows = build_forecast_rows(ridership_df, stops)

    print(f"Prepared {len(rows)} forecast rows from {len(stops)} stops.")
    print("Sample rows:")
    for sample in rows[:8]:
        print(sample)

    if args.dry_run:
        print("Dry-run mode enabled. Skipping Supabase upsert.")
        raise SystemExit(0)

    supabase_url = os.getenv("SUPABASE_URL", "").strip()
    supabase_service_key = os.getenv("SUPABASE_SERVICE_KEY", "").strip()
    if not supabase_url or not supabase_service_key:
        raise RuntimeError("Set SUPABASE_URL and SUPABASE_SERVICE_KEY first.")

    supabase_client = create_client(supabase_url, supabase_service_key)
    upsert_rows(
        client=supabase_client,
        table=args.table,
        rows=rows,
        chunk_size=max(100, args.chunk_size),
    )
    print(f"Completed upsert into {args.table}.")
