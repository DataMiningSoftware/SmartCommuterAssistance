from __future__ import annotations

import argparse
from datetime import datetime, timedelta
import random
from pathlib import Path

import pandas as pd

from crowd_feature_utils import (
    build_feature_row,
    estimate_occupancy_percent,
    load_stop_metadata,
    parse_extra_holiday_dates,
)


def occupancy_level_from_percent(occupancy_percent: float) -> int:
    if occupancy_percent < 12:
        return 1
    if occupancy_percent < 32:
        return 2
    if occupancy_percent < 58:
        return 3
    if occupancy_percent < 82:
        return 4
    return 5


def generate(
    rows: int,
    stops_csv: Path,
    seed: int,
    rain_probability: float,
    global_event_level: float,
) -> pd.DataFrame:
    rng = random.Random(seed)
    stop_metadata = list(load_stop_metadata(stops_csv).values())
    if not stop_metadata:
        raise ValueError(f"No stops available in {stops_csv}")

    extra_holidays = parse_extra_holiday_dates()
    origin = datetime.now().replace(hour=6, minute=0, second=0, microsecond=0)

    rows_out: list[dict[str, object]] = []
    for _ in range(rows):
        stop = rng.choice(stop_metadata)
        when = origin - timedelta(
            days=rng.randint(0, 120),
            hours=rng.randint(0, 17),
            minutes=rng.randint(0, 59),
        )
        is_raining = 1 if rng.random() < rain_probability else 0
        features = build_feature_row(
            stop,
            when,
            is_raining=is_raining,
            rng=rng,
            global_event_level=global_event_level,
            extra_holidays=extra_holidays,
        )

        hour = int(features["hour"])
        day_of_week = int(features["day_of_week"])
        is_weekend = int(features["is_weekend"])
        is_holiday = int(features["is_holiday"])
        event_intensity = int(features["event_intensity"])
        headway_minutes = int(features["headway_minutes"])

        occupancy_percent = estimate_occupancy_percent(
            stop,
            features,
            rng=rng,
        )
        occupancy_level = occupancy_level_from_percent(occupancy_percent)

        rows_out.append(
            {
                "stop_id": stop.stop_id,
                "stop_name": stop.stop_name,
                "route_id": stop.route_id,
                "hour": hour,
                "day_of_week": day_of_week,
                "is_weekend": is_weekend,
                "dow_sin": features["dow_sin"],
                "dow_cos": features["dow_cos"],
                "is_raining": is_raining,
                "is_holiday": is_holiday,
                "peak_period": int(features["peak_period"]),
                "station_pressure": int(features["station_pressure"]),
                "event_intensity": event_intensity,
                "headway_minutes": headway_minutes,
                "occupancy_percent": round(occupancy_percent, 2),
                "occupancy_level": occupancy_level,
            }
        )

    return pd.DataFrame(rows_out)


if __name__ == "__main__":
    script_dir = Path(__file__).resolve().parent
    parser = argparse.ArgumentParser(
        description="Generate richer synthetic crowd data for model training.",
    )
    parser.add_argument("--rows", type=int, default=10000, help="Number of rows")
    parser.add_argument(
        "--stops-csv",
        type=Path,
        default=script_dir / "train_stops_kl.csv",
        help="Path to train_stops_kl.csv",
    )
    parser.add_argument(
        "--output",
        type=Path,
        default=script_dir / "simulated_crowd_data.csv",
        help="Output CSV path",
    )
    parser.add_argument("--seed", type=int, default=42, help="Random seed")
    parser.add_argument(
        "--rain-prob",
        type=float,
        default=0.28,
        help="Probability of rain for each sample",
    )
    parser.add_argument(
        "--event-level",
        type=float,
        default=0.0,
        help="Global event lift applied on top of stop-specific hotspots",
    )
    args = parser.parse_args()

    df = generate(
        rows=args.rows,
        stops_csv=args.stops_csv,
        seed=args.seed,
        rain_probability=args.rain_prob,
        global_event_level=args.event_level,
    )
    args.output.parent.mkdir(parents=True, exist_ok=True)
    df.to_csv(args.output, index=False)
    print(f"Data generated: {args.output}")
    print(df.head(8).to_string(index=False))
