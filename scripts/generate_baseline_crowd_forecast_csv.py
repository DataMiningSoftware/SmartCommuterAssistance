from __future__ import annotations

import argparse
from pathlib import Path

import pandas as pd

COMMERCIAL_STATIONS = {
    "BANDAR UTAMA",
    "BUKIT BINTANG",
    "IMBI",
    "KL SENTRAL",
    "KLCC",
    "MID VALLEY",
    "MUZIUM NEGARA",
    "PASAR SENI",
    "PAVILION DAMANSARA HEIGHTS",
    "TUN RAZAK EXCHANGE (TRX)",
}


def normalize_text(value: object) -> str:
    return str(value or "").strip().upper()


def classify_station_category(row: pd.Series, interchange_names: set[str]) -> str:
    station_name = normalize_text(row.get("station_name"))
    is_interchange = str(row.get("is_interchange", "")).strip().lower() == "true"

    if is_interchange or station_name in interchange_names:
        return "Interchange"
    if station_name in COMMERCIAL_STATIONS:
        return "Commercial"
    return "Residential"


def occupancy_percent_for_level(level: int) -> float:
    return {
        1: 10.0,
        2: 28.0,
        3: 52.0,
        4: 74.0,
        5: 92.0,
    }.get(level, 52.0)


def wait_minutes_for_level(level: int) -> int:
    return {
        1: 2,
        2: 4,
        3: 6,
        4: 8,
        5: 10,
    }.get(level, 4)


def eta_multiplier_for_level(level: int) -> float:
    return {
        1: 1.00,
        2: 1.05,
        3: 1.12,
        4: 1.22,
        5: 1.35,
    }.get(level, 1.10)


def weekday_level(category: str, hour: int) -> int:
    if category == "Residential":
        if hour == 6:
            return 4
        if hour in [7, 8]:
            return 5
        if hour in [17, 18, 19]:
            return 3
        return 1

    if category == "Commercial":
        if hour in [8, 9]:
            return 2
        if hour == 17:
            return 4
        if hour in [18, 19]:
            return 5
        return 2

    if hour == 7:
        return 4
    if hour == 8:
        return 5
    if hour in [17, 18]:
        return 5
    if hour == 19:
        return 4
    return 3


def weekend_level(category: str, hour: int) -> int:
    if category == "Residential":
        if 8 <= hour <= 20:
            return 2
        return 1

    if category == "Commercial":
        if 12 <= hour <= 16:
            return 3
        if 17 <= hour <= 21:
            return 4
        return 2

    if 10 <= hour <= 20:
        return 3
    return 2


def build_station_catalog(stops_csv: Path) -> pd.DataFrame:
    df = pd.read_csv(stops_csv)
    required_columns = {
        "station_id",
        "station_name",
        "line",
        "latitude",
        "longitude",
        "is_interchange",
    }
    missing = required_columns.difference(df.columns)
    if missing:
        raise ValueError(f"Missing required columns: {sorted(missing)}")

    df["station_id"] = df["station_id"].map(normalize_text)
    df["station_name"] = df["station_name"].astype(str).str.strip()
    counts = (
        df.assign(station_name_key=df["station_name"].map(normalize_text))
        .groupby("station_name_key")["line"]
        .nunique()
    )
    interchange_names = {
        station_name for station_name, line_count in counts.items() if line_count > 1
    }
    df["station_category"] = df.apply(
        classify_station_category,
        axis=1,
        interchange_names=interchange_names,
    )
    return df


def build_forecast_rows(catalog: pd.DataFrame) -> pd.DataFrame:
    rows: list[dict[str, object]] = []
    for _, stop in catalog.iterrows():
        stop_id = normalize_text(stop["station_id"])
        category = stop["station_category"]

        for is_weekend in [False, True]:
            for hour in range(24):
                level = (
                    weekend_level(category, hour)
                    if is_weekend
                    else weekday_level(category, hour)
                )
                rows.append(
                    {
                        "stop_id": stop_id,
                        "forecast_hour": hour,
                        "is_weekend": is_weekend,
                        "occupancy_level": level,
                        "occupancy_percent": occupancy_percent_for_level(level),
                        "expected_wait_minutes": wait_minutes_for_level(level),
                        "eta_multiplier": eta_multiplier_for_level(level),
                        "source_type": "baseline_rules",
                    }
                )

    return pd.DataFrame(rows).sort_values(by=["stop_id", "is_weekend", "forecast_hour"])


def parse_args() -> argparse.Namespace:
    script_dir = Path(__file__).resolve().parent
    repo_root = script_dir.parent
    default_stops_csv = repo_root / "app" / "assets" / "train_stops_kl.csv"

    parser = argparse.ArgumentParser(
        description="Generate baseline crowd_forecast_hourly CSV rows from train_stops_kl.csv."
    )
    parser.add_argument(
        "--stops-csv",
        type=Path,
        default=default_stops_csv,
        help="Path to train_stops_kl.csv",
    )
    parser.add_argument(
        "--forecast-output",
        type=Path,
        default=script_dir / "crowd_forecast_hourly_baseline.csv",
        help="Output CSV path matching crowd_forecast_hourly columns",
    )
    parser.add_argument(
        "--catalog-output",
        type=Path,
        default=script_dir / "train_stops_kl_with_categories.csv",
        help="Output CSV path for categorized stop metadata",
    )
    return parser.parse_args()


if __name__ == "__main__":
    args = parse_args()
    catalog = build_station_catalog(args.stops_csv)
    forecast = build_forecast_rows(catalog)

    args.catalog_output.parent.mkdir(parents=True, exist_ok=True)
    args.forecast_output.parent.mkdir(parents=True, exist_ok=True)

    catalog.to_csv(args.catalog_output, index=False)
    forecast.to_csv(args.forecast_output, index=False)

    print(f"Categorized stops written to {args.catalog_output}")
    print(f"Forecast rows written to {args.forecast_output}")
    print(
        catalog[["station_id", "station_name", "station_category"]]
        .head(10)
        .to_string(index=False)
    )
    print(forecast.head(10).to_string(index=False))
