from __future__ import annotations

import os
from datetime import datetime
from pathlib import Path
from zoneinfo import ZoneInfo

import joblib
import requests
from supabase import Client, create_client


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


def predict_level(model, hour: int, is_weekend: int, is_raining: int) -> int:
    return int(model.predict([[hour, is_weekend, is_raining]])[0])


def upsert_predictions(client: Client, stop_ids: list[str], model_path: Path) -> None:
    now = datetime.now(tz=KL_TIMEZONE)
    hour = now.hour
    is_weekend = 1 if now.weekday() >= 5 else 0
    is_raining = get_is_raining()

    model = joblib.load(model_path)
    level = predict_level(model, hour, is_weekend, is_raining)

    print(
        f"Prediction context -> hour={hour}, weekend={is_weekend}, raining={is_raining}, level={level}"
    )

    rows = [
        {
            "stop_id": stop_id,
            "occupancy_level": level,
            "source_type": "predicted",
        }
        for stop_id in stop_ids
    ]
    client.table("crowd_reports").insert(rows).execute()
    print(f"Inserted predictions for {len(rows)} stations.")


if __name__ == "__main__":
    supabase_url = os.getenv("SUPABASE_URL", "").strip()
    supabase_service_key = os.getenv("SUPABASE_SERVICE_KEY", "").strip()
    stop_ids_raw = os.getenv("STOP_IDS", "").strip() or os.getenv("STATION_IDS", "").strip()

    if not supabase_url or not supabase_service_key:
        raise RuntimeError("Set SUPABASE_URL and SUPABASE_SERVICE_KEY first.")
    if not stop_ids_raw:
        raise RuntimeError("Set STOP_IDS (comma-separated stop ids), e.g. PY39,KJ10,AG18")

    stop_ids = [item.strip() for item in stop_ids_raw.split(",") if item.strip()]
    if not stop_ids:
        raise RuntimeError("No valid stop IDs found in STOP_IDS.")

    script_dir = Path(__file__).resolve().parent
    model_file = script_dir / "crowd_predictor.pkl"
    if not model_file.exists():
        raise FileNotFoundError(f"Model file missing: {model_file}")

    supabase_client = create_client(supabase_url, supabase_service_key)
    upsert_predictions(supabase_client, stop_ids, model_file)
