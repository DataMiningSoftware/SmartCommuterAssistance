from __future__ import annotations

import argparse
from datetime import datetime, timedelta
import random
from pathlib import Path

import pandas as pd

from crowd_feature_utils import (
    base_route_pressure,
    build_feature_row,
    load_stop_metadata,
    parse_extra_holiday_dates,
    stop_bias,
)


def occupancy_level_from_percent(occupancy_percent: float) -> int:
    if occupancy_percent < 30:
        return 0
    if occupancy_percent < 60:
        return 1
    if occupancy_percent < 85:
        return 2
    return 3


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
        is_weekend = int(features["is_weekend"])
        is_holiday = int(features["is_holiday"])
        event_intensity = int(features["event_intensity"])
        headway_minutes = int(features["headway_minutes"])

        peak_bonus = 0.0
        if is_weekend == 0 and ((7 <= hour <= 9) or (17 <= hour <= 19)):
            peak_bonus = 24.0
        elif 10 <= hour <= 21:
            peak_bonus = 9.0

        weekend_adjust = -6.0 if is_weekend else 4.0
        holiday_adjust = 8.0 if is_holiday else 0.0
        rain_adjust = 9.0 if is_raining else 0.0
        event_adjust = event_intensity * 7.5
        headway_adjust = max(headway_minutes - 4, 0) * 2.2
        interchange_adjust = 6.0 if stop.is_interchange else 0.0
        noise = rng.uniform(-7.0, 7.0)

        occupancy_percent = (
            15.0
            + base_route_pressure(stop.route_id)
            + peak_bonus
            + weekend_adjust
            + holiday_adjust
            + rain_adjust
            + event_adjust
            + headway_adjust
            + interchange_adjust
            + (stop_bias(stop.stop_id) * 1.6)
            + noise
        )
        occupancy_percent = max(0.0, min(100.0, occupancy_percent))
        occupancy_level = occupancy_level_from_percent(occupancy_percent)

        rows_out.append(
            {
                "stop_id": stop.stop_id,
                "stop_name": stop.stop_name,
                "route_id": stop.route_id,
                "hour": hour,
                "is_weekend": is_weekend,
                "is_raining": is_raining,
                "is_holiday": is_holiday,
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
