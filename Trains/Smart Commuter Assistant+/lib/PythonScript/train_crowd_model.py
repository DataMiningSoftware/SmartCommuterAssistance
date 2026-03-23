from __future__ import annotations

import argparse
from pathlib import Path

import joblib
import pandas as pd
from sklearn.ensemble import RandomForestClassifier
from sklearn.model_selection import train_test_split


def train(data_path: Path, model_path: Path) -> None:
    df = pd.read_csv(data_path)
    x = df[["hour", "is_weekend", "is_raining"]]
    y = df["occupancy_level"]

    x_train, x_test, y_train, y_test = train_test_split(
        x, y, test_size=0.2, random_state=42
    )

    model = RandomForestClassifier(n_estimators=100, random_state=42)
    model.fit(x_train, y_train)

    score = model.score(x_test, y_test) * 100
    print(f"Model Accuracy: {score:.2f}%")

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
