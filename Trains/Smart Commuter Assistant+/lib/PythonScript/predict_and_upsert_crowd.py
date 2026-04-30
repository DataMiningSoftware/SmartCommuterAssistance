from __future__ import annotations

import os
from datetime import datetime
from pathlib import Path
from zoneinfo import ZoneInfo

import joblib
import pandas as pd
import requests
from supabase import Client, create_client

from crowd_feature_utils import (
    build_feature_row,
    load_stop_metadata,
    parse_extra_holiday_dates,
)

KL_TIMEZONE = ZoneInfo("Asia/Kuala_Lumpur")
OPEN_METEO_URL = (
    "https://api.open-meteo.com/v1/forecast"
    "?latitude=3.1390&longitude=101.6869&current=rain"
)


def get_is_raining() -> int:
    try:
        response = requests.get(OPEN_METEO_URL, timeout=8)
        response.raise_for_status()
        payload = response.json()
        rain = float(payload.get("current", {}).get("rain", 0.0))
        return 1 if rain > 0 else 0
    except Exception:
        # Safe fallback when weather API fails.
        return 0


def predict_levels(model, feature_frame: pd.DataFrame) -> list[int]:
    try:
        predictions = model.predict(feature_frame)
    except Exception:
        # Backward compatibility for older 3-feature models.
        legacy_frame = feature_frame[["hour", "is_weekend", "is_raining"]]
        predictions = model.predict(legacy_frame)
    return [int(value) for value in predictions]


def upsert_predictions(
    client: Client,
    stop_ids: list[str],
    model_path: Path,
    stops_csv: Path,
    global_event_level: float,
) -> None:
    now = datetime.now(tz=KL_TIMEZONE)
    is_raining = get_is_raining()
    stop_metadata = load_stop_metadata(stops_csv)
    extra_holidays = parse_extra_holiday_dates()

    model = joblib.load(model_path)
    feature_rows: list[dict[str, object]] = []
    selected_stop_ids: list[str] = []
    for stop_id in stop_ids:
        stop = stop_metadata.get(stop_id.strip().upper())
        if stop is None:
            continue
        features = build_feature_row(
            stop,
            now,
            is_raining=is_raining,
            global_event_level=global_event_level,
            extra_holidays=extra_holidays,
        )
        feature_rows.append(features)
        selected_stop_ids.append(stop.stop_id)

    if not feature_rows:
        raise RuntimeError("No valid stop IDs were found in the stop metadata.")

    feature_frame = pd.DataFrame(feature_rows)
    levels = predict_levels(model, feature_frame)

    print(
        "Prediction context -> "
        f"hour={now.hour}, weekend={1 if now.weekday() >= 5 else 0}, "
        f"raining={is_raining}, rows={len(feature_rows)}"
    )
    print(feature_frame.head(8).to_string(index=False))

    rows = [
        {
            "stop_id": stop_id,
            "occupancy_level": level,
            "source_type": "predicted",
        }
        for stop_id, level in zip(selected_stop_ids, levels)
    ]
    client.table("crowd_reports").insert(rows).execute()
    print(f"Inserted predictions for {len(rows)} stations.")


if __name__ == "__main__":
    supabase_url = os.getenv("SUPABASE_URL", "").strip()
    supabase_service_key = os.getenv("SUPABASE_SERVICE_KEY", "").strip()
    stop_ids_raw = (
        os.getenv("STOP_IDS", "").strip() or os.getenv("STATION_IDS", "").strip()
    )
    global_event_level = float(os.getenv("GLOBAL_EVENT_LEVEL", "0").strip() or 0)

    if not supabase_url or not supabase_service_key:
        raise RuntimeError("Set SUPABASE_URL and SUPABASE_SERVICE_KEY first.")

    script_dir = Path(__file__).resolve().parent
    model_file = script_dir / "crowd_predictor.pkl"
    stops_csv = script_dir / "train_stops_kl.csv"
    if not model_file.exists():
        raise FileNotFoundError(f"Model file missing: {model_file}")
    if not stops_csv.exists():
        raise FileNotFoundError(f"Stops metadata missing: {stops_csv}")

    stop_metadata = load_stop_metadata(stops_csv)
    if stop_ids_raw:
        stop_ids = [item.strip() for item in stop_ids_raw.split(",") if item.strip()]
    else:
        stop_ids = sorted(stop_metadata.keys())
    if not stop_ids:
        raise RuntimeError(
            "No valid stop IDs were supplied or found in train_stops_kl.csv."
        )

    supabase_client = create_client(supabase_url, supabase_service_key)
    upsert_predictions(
        supabase_client,
        stop_ids,
        model_file,
        stops_csv,
        global_event_level,
    )
