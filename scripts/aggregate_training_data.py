from __future__ import annotations

import os
from datetime import datetime, timedelta
from pathlib import Path

import pandas as pd
from supabase import create_client

from crowd_feature_utils import (
    build_feature_row,
    load_stop_metadata,
    parse_extra_holiday_dates,
)

KL_TIMEZONE = "Asia/Kuala_Lumpur"
try:
    from zoneinfo import ZoneInfo

    KL_TZ = ZoneInfo(KL_TIMEZONE)
except ImportError:
    KL_TZ = None

# One reference date per Python weekday (Monday=0 .. Sunday=6) used to rebuild
# day-of-week cyclical features from aggregated report groups.
_DOW_REFERENCE_DATES = [
    pd.Timestamp("2026-04-20"),  # Monday
    pd.Timestamp("2026-04-21"),  # Tuesday
    pd.Timestamp("2026-04-22"),  # Wednesday
    pd.Timestamp("2026-04-23"),  # Thursday
    pd.Timestamp("2026-04-24"),  # Friday
    pd.Timestamp("2026-04-25"),  # Saturday
    pd.Timestamp("2026-04-19"),  # Sunday
]

_PAGE_SIZE = 1000


def _paginated_select(supabase, table: str, columns: str, cutoff: str) -> list[dict]:
    """Fetch all rows since ``cutoff``, paging past PostgREST's 1000-row cap."""
    rows: list[dict] = []
    offset = 0
    while True:
        response = (
            supabase.table(table)
            .select(columns)
            .gte("created_at", cutoff)
            .range(offset, offset + _PAGE_SIZE - 1)
            .execute()
        )
        batch = response.data or []
        rows.extend(batch)
        if len(batch) < _PAGE_SIZE:
            break
        offset += _PAGE_SIZE
    return rows


def pull_real_reports(supabase, days: int = 90) -> pd.DataFrame:
    cutoff = (datetime.now(tz=KL_TZ) - timedelta(days=days)).isoformat()
    rows = _paginated_select(
        supabase,
        "crowd_reports",
        "stop_id,occupancy_level,source_type,created_at,user_id",
        cutoff,
    )
    df = pd.DataFrame(rows)
    if df.empty:
        return pd.DataFrame(columns=["stop_id", "occupancy_level", "source_type", "created_at", "user_id"])
    df["created_at"] = pd.to_datetime(df["created_at"], utc=True).dt.tz_convert(KL_TZ)
    df["hour"] = df["created_at"].dt.hour
    df["day_of_week"] = df["created_at"].dt.dayofweek
    df["is_weekend"] = (df["day_of_week"] >= 5).astype(int)
    return df


def pull_trip_feedback(supabase, days: int = 90) -> pd.DataFrame:
    cutoff = (datetime.now(tz=KL_TZ) - timedelta(days=days)).isoformat()
    rows = _paginated_select(
        supabase,
        "trip_feedback",
        (
            "route_id,origin_stop,dest_stop,predicted_min,actual_min,deviation_min,"
            "crowd_at_start,time_of_day,day_of_week,is_weekend,created_at"
        ),
        cutoff,
    )
    return pd.DataFrame(rows)


def build_training_dataframe(
    reports_df: pd.DataFrame,
    stop_metadata: dict,
    extra_holidays: set,
) -> pd.DataFrame:
    if reports_df.empty or "source_type" not in reports_df.columns:
        return pd.DataFrame()

    user_reports = reports_df[reports_df["source_type"] == "user"].copy()

    if user_reports.empty:
        return pd.DataFrame()

    agg = user_reports.groupby(
        ["stop_id", "hour", "day_of_week", "is_weekend"],
        as_index=False,
    ).agg(
        occupancy_level=("occupancy_level", "median"),
        report_count=("occupancy_level", "count"),
    )

    agg = agg[agg["report_count"] >= 2].copy()

    feature_rows = []
    for _, row in agg.iterrows():
        stop_id = str(row["stop_id"]).strip().upper()
        stop = stop_metadata.get(stop_id)
        if stop is None:
            continue
        day_of_week = int(row["day_of_week"])
        reference = _DOW_REFERENCE_DATES[day_of_week % 7]
        sim_time = reference.to_pydatetime().replace(
            hour=int(row["hour"]),
            minute=0,
            second=0,
            microsecond=0,
        )
        features = build_feature_row(
            stop,
            sim_time,
            is_raining=0,
            rng=None,
            extra_holidays=extra_holidays,
        )
        features["occupancy_level"] = int(round(row["occupancy_level"]))
        features["report_count"] = int(row["report_count"])
        features["source"] = "real_reports"
        feature_rows.append(features)

    if not feature_rows:
        return pd.DataFrame()

    result = pd.DataFrame(feature_rows)

    result["dow_sin"] = pd.to_numeric(result["dow_sin"], errors="coerce").fillna(0)
    result["dow_cos"] = pd.to_numeric(result["dow_cos"], errors="coerce").fillna(1)
    result["occupancy_level"] = result["occupancy_level"].clip(1, 5).astype(int)

    return result


def main():
    supabase_url = os.getenv("SUPABASE_URL", "").strip()
    supabase_key = os.getenv("SUPABASE_SERVICE_KEY", "").strip()

    if not supabase_url or not supabase_key:
        raise RuntimeError("Set SUPABASE_URL and SUPABASE_SERVICE_KEY first.")

    script_dir = Path(__file__).resolve().parent
    stops_csv = script_dir / "train_stops_kl.csv"
    output_path = script_dir / "real_training_data.csv"

    supabase = create_client(supabase_url, supabase_key)
    stop_metadata = load_stop_metadata(stops_csv)
    extra_holidays = parse_extra_holiday_dates()

    print("Pulling real crowd_reports from Supabase...")
    reports = pull_real_reports(supabase, days=90)
    user_report_count = (
        int((reports["source_type"] == "user").sum())
        if not reports.empty and "source_type" in reports.columns
        else 0
    )
    print(f"  Found {len(reports)} total rows, {user_report_count} user reports")

    print("Building training dataframe from real data...")
    training_df = build_training_dataframe(reports, stop_metadata, extra_holidays)

    if training_df.empty:
        print(
            "  Not enough real data to build a training set. "
            "Falling back to simulated data."
        )
        simulated = script_dir / "simulated_crowd_data.csv"
        if simulated.exists():
            df = pd.read_csv(simulated)
            df.to_csv(output_path, index=False)
            print(f"  Copied simulated data to {output_path}")
        return

    training_df.to_csv(output_path, index=False)
    print(f"  Saved {len(training_df)} real-data training rows to {output_path}")

    feedback_df = pull_trip_feedback(supabase, days=90)
    if not feedback_df.empty:
        deviation_path = script_dir / "trip_deviation_summary.csv"
        summary = feedback_df.groupby(
            ["route_id", "time_of_day", "day_of_week"],
            as_index=False,
        ).agg(
            avg_deviation=("deviation_min", "mean"),
            p80_deviation=("deviation_min", lambda x: x.quantile(0.8)),
            sample_count=("deviation_min", "count"),
        )
        summary.to_csv(deviation_path, index=False)
        print(f"  Saved {len(summary)} trip deviation summaries to {deviation_path}")
    else:
        print("  No trip_feedback data yet (no completed trips).")


if __name__ == "__main__":
    main()
