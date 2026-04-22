from __future__ import annotations

import argparse
from pathlib import Path

import numpy as np
import pandas as pd

from crowd_feature_utils import (
    base_route_pressure,
    build_feature_row,
    load_stop_metadata,
    parse_extra_holiday_dates,
    stop_bias,
)

ROUTE_BY_COLUMN = {
    "rail_lrt_ampang": "AG",
    "rail_mrt_kajang": "MRT",
    "rail_lrt_kj": "KJ",
    "rail_monorail": "MR",
    "rail_mrt_pjy": "PYL",
}


def infer_hour_profile(is_weekend: int) -> np.ndarray:
    # Hours 6..23. Weekdays peak around 7-9 and 17-19.
    hours = np.arange(6, 24)
    if is_weekend:
        profile = np.array(
            [0.05, 0.05, 0.06, 0.06, 0.07, 0.08, 0.08, 0.08, 0.08, 0.08, 0.07, 0.06, 0.06, 0.06, 0.06, 0.06, 0.05, 0.05]
        )
    else:
        profile = np.array(
            [0.04, 0.10, 0.12, 0.10, 0.06, 0.05, 0.05, 0.05, 0.05, 0.06, 0.09, 0.12, 0.12, 0.09, 0.05, 0.03, 0.01, 0.01]
        )
    return profile / profile.sum()


def occupancy_level_from_percent(occupancy_percent: float) -> int:
    if occupancy_percent < 30:
        return 0
    if occupancy_percent < 60:
        return 1
    if occupancy_percent < 85:
        return 2
    return 3


def build_trend_tables(df: pd.DataFrame) -> tuple[pd.DataFrame, pd.Series]:
    rail_cols = [col for col in ROUTE_BY_COLUMN if col in df.columns]
    long_df = df.melt(
        id_vars=["date"],
        value_vars=rail_cols,
        var_name="trend_column",
        value_name="ridership",
    ).dropna(subset=["ridership"])

    long_df["ridership"] = pd.to_numeric(long_df["ridership"], errors="coerce")
    long_df = long_df.dropna(subset=["ridership"])
    long_df["dow"] = long_df["date"].dt.dayofweek
    long_df["route_id"] = long_df["trend_column"].map(ROUTE_BY_COLUMN)
    long_df = long_df.dropna(subset=["route_id"])

    route_dow_mean = long_df.groupby(["route_id", "dow"])["ridership"].mean().unstack(fill_value=0.0)
    route_overall = long_df.groupby("route_id")["ridership"].mean()
    return route_dow_mean, route_overall


def simulate_from_trends(
    df: pd.DataFrame,
    stops_csv: Path,
    rows: int = 10_000,
    rain_probability: float = 0.28,
    seed: int = 42,
    global_event_level: float = 0.0,
) -> pd.DataFrame:
    rng = np.random.default_rng(seed)
    route_dow_mean, route_overall = build_trend_tables(df)
    route_ids = route_overall.index.to_list()
    if not route_ids:
        raise ValueError("No supported ridership columns found in the input CSV.")

    stop_metadata = load_stop_metadata(stops_csv)
    stops_by_route: dict[str, list] = {}
    for stop in stop_metadata.values():
        stops_by_route.setdefault(stop.route_id, []).append(stop)

    route_ids = [route_id for route_id in route_ids if route_id in stops_by_route]
    if not route_ids:
        raise ValueError("Ridership routes do not overlap with the stop metadata.")

    route_weights = route_overall.loc[route_ids].to_numpy()
    route_weights = route_weights / route_weights.sum()
    global_max = max(route_dow_mean.to_numpy().max(), 1.0)
    extra_holidays = parse_extra_holiday_dates()

    out_rows: list[dict[str, object]] = []
    for _ in range(rows):
        route_id = str(rng.choice(route_ids, p=route_weights))
        stop = stops_by_route[route_id][int(rng.integers(0, len(stops_by_route[route_id])))]
        is_weekend = int(rng.choice([0, 1], p=[5 / 7, 2 / 7]))

        if is_weekend == 1:
            dow = int(rng.choice([5, 6]))
        else:
            dow = int(rng.choice([0, 1, 2, 3, 4]))

        hour_probs = infer_hour_profile(is_weekend)
        hour = int(rng.choice(np.arange(6, 24), p=hour_probs))

        minute = int(rng.choice(np.arange(0, 60)))
        when = pd.Timestamp.now().normalize() - pd.Timedelta(days=int(rng.integers(0, 120)))
        when = when.to_pydatetime().replace(hour=hour, minute=minute)

        is_raining = int(
            rng.choice([0, 1], p=[1 - rain_probability, rain_probability])
        )
        features = build_feature_row(
            stop,
            when,
            is_raining=is_raining,
            global_event_level=global_event_level,
            extra_holidays=extra_holidays,
        )

        trend_value = (
            float(route_dow_mean.loc[route_id, dow])
            if route_id in route_dow_mean.index
            else float(route_overall.mean())
        )
        trend_norm = np.clip(trend_value / global_max, 0.0, 1.0)

        hour_peak = 0.0
        if 7 <= hour <= 9:
            hour_peak = 0.30
        elif 17 <= hour <= 19:
            hour_peak = 0.34
        elif 6 <= hour <= 22:
            hour_peak = 0.12

        holiday_adjust = 0.08 if int(features["is_holiday"]) else 0.0
        weekend_adjust = -0.08 if is_weekend else 0.08
        rain_adjust = rng.uniform(0.06, 0.16) if is_raining else 0.0
        event_adjust = int(features["event_intensity"]) * 0.08
        headway_adjust = max(int(features["headway_minutes"]) - 4, 0) * 0.018
        interchange_adjust = 0.05 if stop.is_interchange else 0.0
        stop_adjust = stop_bias(stop.stop_id) / 120.0
        route_adjust = base_route_pressure(route_id) / 140.0
        noise = rng.normal(0.0, 0.05)

        occupancy_percent = 100.0 * (
            0.10
            + (0.45 * trend_norm)
            + route_adjust
            + hour_peak
            + weekend_adjust
            + holiday_adjust
            + rain_adjust
            + event_adjust
            + headway_adjust
            + interchange_adjust
            + stop_adjust
            + noise
        )
        occupancy_percent = float(np.clip(occupancy_percent, 0.0, 100.0))
        occupancy_level = occupancy_level_from_percent(occupancy_percent)

        out_rows.append(
            {
                "stop_id": stop.stop_id,
                "stop_name": stop.stop_name,
                "route_id": route_id,
                "hour": hour,
                "is_weekend": is_weekend,
                "is_raining": is_raining,
                "is_holiday": int(features["is_holiday"]),
                "event_intensity": int(features["event_intensity"]),
                "headway_minutes": int(features["headway_minutes"]),
                "occupancy_percent": round(occupancy_percent, 2),
                "occupancy_level": occupancy_level,
            }
        )

    return pd.DataFrame(out_rows)


def parse_args() -> argparse.Namespace:
    script_dir = Path(__file__).resolve().parent
    return argparse.ArgumentParser(
        description="Generate synthetic crowd data using historical ridership trends."
    ).parse_args()


if __name__ == "__main__":
    parser = argparse.ArgumentParser(
        description="Generate synthetic crowd data using historical ridership trends."
    )
    parser.add_argument(
        "--input",
        type=Path,
        required=True,
        help="Path to ridership_headline.csv",
    )
    parser.add_argument(
        "--output",
        type=Path,
        default=Path(__file__).resolve().parent / "simulated_crowd_data_from_trends.csv",
        help="Output CSV path for simulated rows",
    )
    parser.add_argument(
        "--stops-csv",
        type=Path,
        default=Path(__file__).resolve().parent / "train_stops_kl.csv",
        help="Path to train_stops_kl.csv",
    )
    parser.add_argument("--rows", type=int, default=10000, help="Number of synthetic rows")
    parser.add_argument("--rain-prob", type=float, default=0.28, help="Rain probability (0..1)")
    parser.add_argument("--seed", type=int, default=42, help="Random seed")
    parser.add_argument(
        "--event-level",
        type=float,
        default=0.0,
        help="Global event lift applied on top of hotspot stations",
    )
    args = parser.parse_args()

    source_df = pd.read_csv(args.input, parse_dates=["date"])
    simulated = simulate_from_trends(
        source_df,
        stops_csv=args.stops_csv,
        rows=args.rows,
        rain_probability=args.rain_prob,
        seed=args.seed,
        global_event_level=args.event_level,
    )
    args.output.parent.mkdir(parents=True, exist_ok=True)
    simulated.to_csv(args.output, index=False)

    print(f"Generated {len(simulated)} rows -> {args.output}")
    print("Sample:")
    print(simulated.head(8).to_string(index=False))
