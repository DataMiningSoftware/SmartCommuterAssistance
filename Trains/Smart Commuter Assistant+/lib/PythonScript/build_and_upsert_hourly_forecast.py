from __future__ import annotations

import argparse
import os
from pathlib import Path

import pandas as pd
from supabase import Client, create_client

from crowd_feature_utils import (
    build_feature_row,
    estimate_occupancy_percent,
    load_stop_metadata,
    normalize_route_id,
    parse_extra_holiday_dates,
)


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
            mean_value = (
                float(scoped.dropna().mean()) if not scoped.dropna().empty else 0.0
            )
            strengths[(route, is_weekend)] = mean_value
            if mean_value > 0:
                fallback_values.append(mean_value)

    fallback_mean = (
        float(sum(fallback_values) / len(fallback_values))
        if fallback_values
        else 1.0
    )
    for route in ["KJ", "AG", "MRT", "PYL", "MR", "BRT"]:
        for is_weekend in [False, True]:
            strengths.setdefault((route, is_weekend), fallback_mean)

    max_value = max(strengths.values()) if strengths else 1.0
    if max_value <= 0:
        max_value = 1.0

    return {key: (value / max_value) for key, value in strengths.items()}


def build_forecast_rows(
    ridership_df: pd.DataFrame,
    stops_csv: Path,
    global_event_level: float = 0.0,
) -> list[dict[str, object]]:
    line_strength = compute_line_strength(ridership_df)
    extra_holidays = parse_extra_holiday_dates()
    stops = list(load_stop_metadata(stops_csv).values())
    rows: list[dict[str, object]] = []

    weekday_reference = pd.Timestamp("2026-04-21")
    weekend_reference = pd.Timestamp("2026-04-19")

    for stop in stops:
        route = normalize_route_id(stop.route_id, stop.stop_id)
        for is_weekend in [False, True]:
            line_value = line_strength.get((route, is_weekend), 0.55)
            reference = weekend_reference if is_weekend else weekday_reference

            for hour in range(24):
                when = reference.to_pydatetime().replace(hour=hour, minute=30)
                features = build_feature_row(
                    stop,
                    when,
                    is_raining=0,
                    global_event_level=global_event_level,
                    extra_holidays=extra_holidays,
                )
                percent = estimate_occupancy_percent(
                    stop,
                    features,
                    trend_strength=line_value,
                )

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


def chunked(
    items: list[dict[str, object]],
    chunk_size: int,
) -> list[list[dict[str, object]]]:
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
        "--event-level",
        type=float,
        default=0.0,
        help="Global event lift applied on top of hotspot stations",
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
    rows = build_forecast_rows(
        ridership_df,
        stops_csv=stops_csv,
        global_event_level=args.event_level,
    )

    print(f"Prepared {len(rows)} forecast rows.")
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
