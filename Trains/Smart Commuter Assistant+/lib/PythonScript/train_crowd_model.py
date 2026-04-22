from __future__ import annotations

import argparse
from pathlib import Path

import joblib
import pandas as pd
from sklearn.compose import ColumnTransformer
from sklearn.ensemble import RandomForestClassifier
from sklearn.metrics import accuracy_score
from sklearn.model_selection import train_test_split
from sklearn.pipeline import Pipeline
from sklearn.preprocessing import OneHotEncoder


FEATURE_COLUMNS = [
    "stop_id",
    "route_id",
    "hour",
    "is_weekend",
    "is_raining",
    "is_holiday",
    "peak_period",
    "station_pressure",
    "event_intensity",
    "headway_minutes",
]

CATEGORICAL_FEATURES = ["stop_id", "route_id"]
NUMERIC_FEATURES = [
    "hour",
    "is_weekend",
    "is_raining",
    "is_holiday",
    "peak_period",
    "station_pressure",
    "event_intensity",
    "headway_minutes",
]


def _ensure_feature_columns(df: pd.DataFrame) -> pd.DataFrame:
    enriched = df.copy()
    defaults = {
        "stop_id": "UNKNOWN_STOP",
        "route_id": "KJ",
        "hour": 12,
        "is_weekend": 0,
        "is_raining": 0,
        "is_holiday": 0,
        "peak_period": 0,
        "station_pressure": 0,
        "event_intensity": 0,
        "headway_minutes": 6,
    }

    for column, default_value in defaults.items():
        if column not in enriched.columns:
            enriched[column] = default_value

    for column in NUMERIC_FEATURES:
        enriched[column] = pd.to_numeric(enriched[column], errors="coerce").fillna(
            defaults[column]
        )

    for column in CATEGORICAL_FEATURES:
        enriched[column] = enriched[column].astype(str).fillna(defaults[column])

    return enriched


def train(data_path: Path, model_path: Path) -> None:
    df = _ensure_feature_columns(pd.read_csv(data_path))
    if "occupancy_level" not in df.columns:
        raise ValueError(f"Missing occupancy_level column in {data_path}")

    x = df[FEATURE_COLUMNS]
    y = pd.to_numeric(df["occupancy_level"], errors="coerce").fillna(0).astype(int)

    x_train, x_test, y_train, y_test = train_test_split(
        x,
        y,
        test_size=0.2,
        random_state=42,
        stratify=y if y.nunique() > 1 else None,
    )

    preprocessor = ColumnTransformer(
        transformers=[
            (
                "categorical",
                OneHotEncoder(handle_unknown="ignore"),
                CATEGORICAL_FEATURES,
            ),
            ("numeric", "passthrough", NUMERIC_FEATURES),
        ]
    )
    model = Pipeline(
        steps=[
            ("preprocessor", preprocessor),
            (
                "classifier",
                RandomForestClassifier(
                    n_estimators=220,
                    min_samples_leaf=2,
                    random_state=42,
                ),
            ),
        ]
    )
    model.fit(x_train, y_train)

    predictions = model.predict(x_test)
    score = accuracy_score(y_test, predictions) * 100
    print(f"Model Accuracy: {score:.2f}%")
    print(f"Training rows: {len(x_train)} | Test rows: {len(x_test)}")
    print(f"Features used: {', '.join(FEATURE_COLUMNS)}")

    joblib.dump(model, model_path)
    print(f"Model saved: {model_path}")


if __name__ == "__main__":
    script_dir = Path(__file__).resolve().parent
    parser = argparse.ArgumentParser(description="Train crowd prediction model.")
    parser.add_argument(
        "--input",
        type=Path,
        default=script_dir / "simulated_crowd_data.csv",
        help="Training CSV path",
    )
    parser.add_argument(
        "--output",
        type=Path,
        default=script_dir / "crowd_predictor.pkl",
        help="Output model .pkl path",
    )
    args = parser.parse_args()

    data_file = args.input
    model_file = args.output
    train(data_file, model_file)
