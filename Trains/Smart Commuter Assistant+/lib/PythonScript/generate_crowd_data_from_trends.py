from __future__ import annotations

import argparse
from pathlib import Path

import numpy as np
import pandas as pd


RAIL_COLUMNS = [
    "rail_lrt_ampang",
    "rail_mrt_kajang",
    "rail_lrt_kj",
    "rail_monorail",
    "rail_mrt_pjy",
    "rail_ets",
    "rail_intercity",
    "rail_komuter_utara",
    "rail_tebrau",
    "rail_komuter",
]


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
    rail_cols = [col for col in RAIL_COLUMNS if col in df.columns]
    long_df = df.melt(
        id_vars=["date"],
        value_vars=rail_cols,
        var_name="line_id",
        value_name="ridership",
    ).dropna(subset=["ridership"])

    long_df["ridership"] = pd.to_numeric(long_df["ridership"], errors="coerce")
    long_df = long_df.dropna(subset=["ridership"])
    long_df["dow"] = long_df["date"].dt.dayofweek

    # Mean ridership by line + day-of-week captures observed trend shape.
    line_dow_mean = long_df.groupby(["line_id", "dow"])["ridership"].mean().unstack(fill_value=0.0)
    line_overall = long_df.groupby("line_id")["ridership"].mean()
    return line_dow_mean, line_overall


def simulate_from_trends(
    df: pd.DataFrame,
    rows: int = 10_000,
    rain_probability: float = 0.28,
    seed: int = 42,
) -> pd.DataFrame:
    rng = np.random.default_rng(seed)
    line_dow_mean, line_overall = build_trend_tables(df)
    lines = line_overall.index.to_list()

    line_weights = (line_overall / line_overall.sum()).to_numpy()
    global_max = max(line_dow_mean.to_numpy().max(), 1.0)

    out_rows: list[dict[str, object]] = []
    for _ in range(rows):
        line_id = str(rng.choice(lines, p=line_weights))
        is_weekend = int(rng.choice([0, 1], p=[5 / 7, 2 / 7]))

        # Pick weekday index. 0..4 for weekdays, 5..6 for weekends.
        if is_weekend == 1:
            dow = int(rng.choice([5, 6]))
        else:
            dow = int(rng.choice([0, 1, 2, 3, 4]))

        hour_probs = infer_hour_profile(is_weekend)
        hour = int(rng.choice(np.arange(6, 24), p=hour_probs))

        is_raining = int(rng.choice([0, 1], p=[1 - rain_probability, rain_probability]))

        # Trend score from historical ridership for selected line/day.
        trend_value = float(line_dow_mean.loc[line_id, dow]) if line_id in line_dow_mean.index else float(line_overall.mean())
        trend_norm = np.clip(trend_value / global_max, 0.0, 1.0)

        # Hour pressure: stronger during commute peaks.
        hour_peak = 0.0
        if 7 <= hour <= 9:
            hour_peak = 0.36
        elif 17 <= hour <= 19:
            hour_peak = 0.42
        elif 6 <= hour <= 22:
            hour_peak = 0.18

        weekend_adjust = -0.16 if is_weekend else 0.10
        rain_adjust = rng.uniform(0.08, 0.18) if is_raining else 0.0
        noise = rng.normal(0.0, 0.07)

        occupancy_percent = (
            100.0 * (0.10 + (0.55 * trend_norm) + hour_peak + weekend_adjust + rain_adjust + noise)
        )
        occupancy_percent = float(np.clip(occupancy_percent, 0.0, 100.0))
        occupancy_level = occupancy_level_from_percent(occupancy_percent)

        out_rows.append(
            {
                "line_id": line_id.replace("rail_", ""),
                "hour": hour,
                "is_weekend": is_weekend,
                "is_raining": is_raining,
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
    parser.add_argument("--rows", type=int, default=10000, help="Number of synthetic rows")
    parser.add_argument("--rain-prob", type=float, default=0.28, help="Rain probability (0..1)")
    parser.add_argument("--seed", type=int, default=42, help="Random seed")
    args = parser.parse_args()

    source_df = pd.read_csv(args.input, parse_dates=["date"])
    simulated = simulate_from_trends(
        source_df,
        rows=args.rows,
        rain_probability=args.rain_prob,
        seed=args.seed,
    )
    args.output.parent.mkdir(parents=True, exist_ok=True)
    simulated.to_csv(args.output, index=False)

    print(f"Generated {len(simulated)} rows -> {args.output}")
    print("Sample:")
    print(simulated.head(8).to_string(index=False))
