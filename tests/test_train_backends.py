import pandas as pd
from pathlib import Path

from train_crowd_model import train


def _make_tiny_dataset(tmp_path: Path) -> Path:
    df = pd.DataFrame(
        [
            {
                "stop_id": "S1",
                "route_id": "R1",
                "hour": 8,
                "is_weekend": 0,
                "is_raining": 0,
                "is_holiday": 0,
                "peak_period": 1,
                "station_pressure": 1,
                "event_intensity": 0,
                "headway_minutes": 5,
                "occupancy_level": 4,
            },
            {
                "stop_id": "S2",
                "route_id": "R1",
                "hour": 9,
                "is_weekend": 0,
                "is_raining": 0,
                "is_holiday": 0,
                "peak_period": 1,
                "station_pressure": 1,
                "event_intensity": 0,
                "headway_minutes": 6,
                "occupancy_level": 3,
            },
            {
                "stop_id": "S1",
                "route_id": "R2",
                "hour": 14,
                "is_weekend": 1,
                "is_raining": 0,
                "is_holiday": 0,
                "peak_period": 0,
                "station_pressure": 0,
                "event_intensity": 0,
                "headway_minutes": 10,
                "occupancy_level": 2,
            },
            {
                "stop_id": "S3",
                "route_id": "R2",
                "hour": 23,
                "is_weekend": 0,
                "is_raining": 1,
                "is_holiday": 0,
                "peak_period": 0,
                "station_pressure": 0,
                "event_intensity": 0,
                "headway_minutes": 12,
                "occupancy_level": 1,
            },
        ]
    )
    path = tmp_path / "tiny.csv"
    df.to_csv(path, index=False)
    return path


def test_train_backends(tmp_path):
    data = _make_tiny_dataset(tmp_path)
    out = tmp_path / "model.pkl"

    # Train with RF
    train(data, out, model_choice="rf", do_tune=False, optuna_trials=1)

    # Train with LightGBM
    train(data, out, model_choice="lgbm", do_tune=False, optuna_trials=1)

    # Train with XGBoost
    train(data, out, model_choice="xgb", do_tune=False, optuna_trials=1)

    assert out.exists()
