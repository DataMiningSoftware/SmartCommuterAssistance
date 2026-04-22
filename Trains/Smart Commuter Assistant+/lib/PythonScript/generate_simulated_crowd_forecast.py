from __future__ import annotations

import argparse
from dataclasses import dataclass
from datetime import time
from pathlib import Path

import pandas as pd


FIRST_TRAIN = "06:00"
LAST_TRAIN = "00:00"
CLOSED_HEADWAY = -1

# Hourly rows are evaluated at HH:30 so half-hour crowd windows are preserved.
FORECAST_MINUTE = 30

COMMERCIAL_KEYWORDS = (
    "ABDULLAH HUKUM",
    "BANDAR UTAMA",
    "BUKIT BINTANG",
    "IMBI",
    "KL SENTRAL",
    "KLCC",
    "MID VALLEY",
    "MUZIUM NEGARA",
    "PASAR SENI",
    "PAVILION DAMANSARA HEIGHTS",
    "PERSIARAN KLCC",
    "TRX",
    "TUN RAZAK EXCHANGE",
)

DAY_TYPES = ("Weekday", "Weekend")

HEADWAY_WINDOWS = (
    (6 * 60, 7 * 60, 5),
    (7 * 60, 9 * 60 + 30, 3),
    (9 * 60 + 30, 16 * 60 + 30, 7),
    (16 * 60 + 30, 19 * 60 + 30, 3),
    (19 * 60 + 30, 22 * 60, 8),
    (22 * 60, 24 * 60, 15),
)


@dataclass(frozen=True)
class StationProfile:
    station_id: str
    station_name: str
    station_type: str
    first_train: str = FIRST_TRAIN
    last_train: str = LAST_TRAIN


def normalize_text(value: object) -> str:
    uppercase = str(value or "").strip().upper()
    cleaned = "".join(ch if ch.isalnum() else " " for ch in uppercase)
    return " ".join(cleaned.split())


def parse_bool(value: object) -> bool:
    return str(value or "").strip().lower() in {"true", "1", "yes"}


def minutes_since_midnight(current_time: time) -> int:
    return (current_time.hour * 60) + current_time.minute


def station_type_for(row: pd.Series) -> str:
    station_name = normalize_text(row.get("stop_name"))
    if parse_bool(row.get("is_interchange")):
        return "Interchange"
    if any(keyword in station_name for keyword in COMMERCIAL_KEYWORDS):
        return "Commercial"
    return "Residential"


def is_operating(current_time: time) -> bool:
    current_minutes = minutes_since_midnight(current_time)
    return 6 * 60 <= current_minutes < 24 * 60


def service_frequency_minutes(current_time: time) -> tuple[int, int] | None:
    current_minutes = minutes_since_midnight(current_time)
    for start_minutes, end_minutes, frequency in HEADWAY_WINDOWS:
        if start_minutes <= current_minutes < end_minutes:
            return start_minutes, frequency
    return None


def minutes_until_next_train(current_time: time) -> int | None:
    window = service_frequency_minutes(current_time)
    if window is None:
        return None

    start_minutes, frequency = window
    elapsed = minutes_since_midnight(current_time) - start_minutes
    remainder = elapsed % frequency
    if remainder == 0:
        return 0
    return frequency - remainder


def in_window(current_time: time, start_hour: int, start_minute: int, end_hour: int, end_minute: int) -> bool:
    current_minutes = minutes_since_midnight(current_time)
    start_minutes = (start_hour * 60) + start_minute
    end_minutes = (end_hour * 60) + end_minute
    return start_minutes <= current_minutes <= end_minutes


def baseline_level(station_type: str, day_type: str) -> int:
    if day_type == "Weekend":
        return 2 if station_type in {"Commercial", "Interchange"} else 1
    return 2 if station_type in {"Commercial", "Interchange"} else 1


def predicted_crowd_level(station_type: str, day_type: str, current_time: time) -> int:
    if not is_operating(current_time):
        return 1

    if day_type == "Weekday":
        if station_type == "Residential":
            if in_window(current_time, 6, 30, 7, 29):
                return 4
            if in_window(current_time, 7, 30, 8, 30):
                return 5
            if in_window(current_time, 17, 30, 19, 30):
                return 3
            return baseline_level(station_type, day_type)

        if station_type == "Commercial":
            if in_window(current_time, 8, 0, 9, 30):
                return 2
            if in_window(current_time, 17, 30, 18, 29):
                return 4
            if in_window(current_time, 18, 30, 19, 30):
                return 5
            return baseline_level(station_type, day_type)

        if in_window(current_time, 7, 30, 8, 30):
            return 5
        if in_window(current_time, 17, 30, 19, 0):
            return 5
        return baseline_level(station_type, day_type)

    if station_type == "Residential":
        if in_window(current_time, 10, 0, 21, 0):
            return 2
        return 1

    if station_type == "Commercial":
        if in_window(current_time, 12, 0, 16, 59):
            return 3
        if in_window(current_time, 17, 0, 21, 0):
            return 4
        return baseline_level(station_type, day_type)

    if in_window(current_time, 10, 0, 20, 0):
        return 3
    return baseline_level(station_type, day_type)


def load_station_profiles(stops_csv: Path) -> list[StationProfile]:
    stops = pd.read_csv(stops_csv)
    required_columns = {"stop_id", "stop_name", "is_interchange"}
    missing = required_columns.difference(stops.columns)
    if missing:
        raise ValueError(f"Missing required columns in {stops_csv}: {sorted(missing)}")

    profiles: list[StationProfile] = []
    for _, row in stops.iterrows():
        station_id = str(row.get("stop_id", "")).strip().upper()
        station_name = str(row.get("stop_name", "")).strip()
        if not station_id or not station_name:
            continue
        profiles.append(
            StationProfile(
                station_id=station_id,
                station_name=station_name,
                station_type=station_type_for(row),
            )
        )

    if not profiles:
        raise ValueError(f"No valid stations were found in {stops_csv}")
    return profiles


def build_forecast_rows(profiles: list[StationProfile]) -> pd.DataFrame:
    rows: list[dict[str, object]] = []
    for profile in profiles:
        for day_type in DAY_TYPES:
            for hour in range(24):
                current_time = time(hour=hour, minute=FORECAST_MINUTE)
                operating = is_operating(current_time)
                headway = minutes_until_next_train(current_time)
                rows.append(
                    {
                        "station_id": profile.station_id,
                        "day_type": day_type,
                        "hour_of_day": hour,
                        "predicted_crowd_level": predicted_crowd_level(
                            profile.station_type,
                            day_type,
                            current_time,
                        ),
                        "minutes_until_next_train": (
                            headway if operating and headway is not None else CLOSED_HEADWAY
                        ),
                        "is_operating": operating,
                    }
                )

    return pd.DataFrame(rows).sort_values(
        by=["station_id", "day_type", "hour_of_day"],
        ignore_index=True,
    )


def parse_args() -> argparse.Namespace:
    script_dir = Path(__file__).resolve().parent
    parser = argparse.ArgumentParser(
        description="Generate a simulated 24-hour crowd forecast CSV for train_stops_kl.csv.",
    )
    parser.add_argument(
        "--stops-csv",
        type=Path,
        default=script_dir / "train_stops_kl.csv",
        help="Path to train_stops_kl.csv",
    )
    parser.add_argument(
        "--output",
        type=Path,
        default=script_dir / "simulated_crowd_forecast.csv",
        help="Output CSV path",
    )
    return parser.parse_args()


if __name__ == "__main__":
    args = parse_args()
    profiles = load_station_profiles(args.stops_csv)
    forecast = build_forecast_rows(profiles)

    args.output.parent.mkdir(parents=True, exist_ok=True)
    forecast.to_csv(args.output, index=False)

    print(f"Generated {len(forecast)} forecast rows at {args.output}")
    print(forecast.head(12).to_string(index=False))
