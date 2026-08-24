from __future__ import annotations

import argparse
from pathlib import Path
import json
import os
from typing import Any, Dict

import joblib
import pandas as pd
import numpy as np
from sklearn.compose import ColumnTransformer
from sklearn.metrics import accuracy_score
from sklearn.model_selection import TimeSeriesSplit, train_test_split
from sklearn.pipeline import Pipeline
from sklearn.preprocessing import OneHotEncoder

FEATURE_COLUMNS = [
    "stop_id",
    "route_id",
    "hour",
    "is_weekend",
    "day_of_week",
    "dow_sin",
    "dow_cos",
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
    "day_of_week",
    "dow_sin",
    "dow_cos",
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
        "day_of_week": 0,
        "dow_sin": 0.0,
        "dow_cos": 1.0,
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


def train(
    data_path: Path,
    model_path: Path,
    model_choice: str | None = None,
    do_tune: bool | None = None,
    optuna_trials: int | None = None,
) -> None:
    df = _ensure_feature_columns(pd.read_csv(data_path))
    if "occupancy_level" not in df.columns:
        raise ValueError(f"Missing occupancy_level column in {data_path}")

    x = df[FEATURE_COLUMNS]
    y = pd.to_numeric(df["occupancy_level"], errors="coerce").fillna(0).astype(int)

    # Use time-based split for realistic forecasting evaluation.
    # Sorts rows by an inferred timestamp and takes the most recent 20% as test.
    # If no timestamp column is available, falls back to random split.
    time_cols = ["timestamp", "date", "datetime", "ds", "time"]
    ts_col = next((c for c in time_cols if c in df.columns), None)
    if ts_col is not None:
        sorted_idx = df[ts_col].sort_values().index
        split_idx = int(len(sorted_idx) * 0.8)
        train_idx = sorted_idx[:split_idx]
        test_idx = sorted_idx[split_idx:]
        x_train, x_test = x.loc[train_idx], x.loc[test_idx]
        y_train, y_test = y.loc[train_idx], y.loc[test_idx]
        print(f"Time-based split: {len(x_train)} train, {len(x_test)} test rows")
    else:
        try:
            stratify_for_split = y if (y.value_counts().min() >= 2) else None
        except Exception:
            stratify_for_split = None

        x_train, x_test, y_train, y_test = train_test_split(
            x,
            y,
            test_size=0.2,
            random_state=42,
            stratify=stratify_for_split,
        )
        print("No timestamp column found, fell back to random split")

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

    def _get_classifier(choice: str, params: Dict[str, Any]):
        if choice == "rf":
            from sklearn.ensemble import RandomForestClassifier

            return RandomForestClassifier(**params)
        if choice == "lgbm":
            import lightgbm as lgb

            return lgb.LGBMClassifier(**params)
        if choice == "xgb":
            import xgboost as xgb

            # use_label_encoder is deprecated in newer xgboost versions; set safe defaults
            params = {**params}
            params.setdefault("use_label_encoder", False)
            params.setdefault("verbosity", 0)
            params.setdefault("eval_metric", "mlogloss")
            return xgb.XGBClassifier(**params)

        raise ValueError(f"Unknown model choice: {choice}")

    def _default_params(choice: str) -> Dict[str, Any]:
        if choice == "rf":
            return {
                "n_estimators": 220,
                "min_samples_leaf": 2,
                "random_state": 42,
                "n_jobs": -1,
            }
        if choice == "lgbm":
            return {"n_estimators": 220, "random_state": 42, "n_jobs": -1}
        if choice == "xgb":
            return {"n_estimators": 220, "random_state": 42, "n_jobs": -1}
        return {}

    def _suggest_params(trial, choice: str) -> Dict[str, Any]:
        if choice == "rf":
            return {
                "n_estimators": trial.suggest_int("n_estimators", 50, 500),
                "max_depth": trial.suggest_int("max_depth", 3, 32),
                "min_samples_leaf": trial.suggest_int("min_samples_leaf", 1, 10),
                "max_features": trial.suggest_categorical(
                    "max_features", ["sqrt", "log2", "auto"]
                ),
                "random_state": 42,
                "n_jobs": -1,
            }
        if choice == "lgbm":
            return {
                "n_estimators": trial.suggest_int("n_estimators", 50, 2000),
                "num_leaves": trial.suggest_int("num_leaves", 16, 256),
                "max_depth": trial.suggest_int("max_depth", -1, 16),
                "learning_rate": trial.suggest_float(
                    "learning_rate", 1e-4, 0.3, log=True
                ),
                "min_child_samples": trial.suggest_int("min_child_samples", 5, 100),
                "subsample": trial.suggest_float("subsample", 0.5, 1.0),
                "colsample_bytree": trial.suggest_float("colsample_bytree", 0.5, 1.0),
                "reg_alpha": trial.suggest_float("reg_alpha", 0.0, 1.0),
                "reg_lambda": trial.suggest_float("reg_lambda", 0.0, 1.0),
                "random_state": 42,
                "n_jobs": -1,
            }
        if choice == "xgb":
            return {
                "n_estimators": trial.suggest_int("n_estimators", 50, 2000),
                "max_depth": trial.suggest_int("max_depth", 3, 16),
                "learning_rate": trial.suggest_float(
                    "learning_rate", 1e-4, 0.3, log=True
                ),
                "subsample": trial.suggest_float("subsample", 0.5, 1.0),
                "colsample_bytree": trial.suggest_float("colsample_bytree", 0.5, 1.0),
                "reg_alpha": trial.suggest_float("reg_alpha", 0.0, 1.0),
                "reg_lambda": trial.suggest_float("reg_lambda", 0.0, 1.0),
                "random_state": 42,
                "n_jobs": -1,
            }
        return {}

    # allow switching models and optuna tuning via function args or environment vars
    if model_choice is None:
        model_choice = os.getenv("SCA_MODEL", "rf").lower()
    else:
        model_choice = model_choice.lower()

    if do_tune is None:
        do_tune = os.getenv("SCA_TUNE", "").lower() in ("1", "true", "yes")

    if optuna_trials is None:
        optuna_trials = int(os.getenv("SCA_TRIALS", "50"))

    # Label mapping used for models (XGBoost sometimes requires contiguous 0..n-1 labels)
    label_map = None
    if model_choice == "xgb":
        try:
            from sklearn.preprocessing import LabelEncoder

            le = LabelEncoder()
            # Fit on all available labels so mapping covers train/val/test
            le.fit(pd.concat([y_train, y_test]))
            y_train = pd.Series(le.transform(y_train), index=y_train.index)
            y_test = pd.Series(le.transform(y_test), index=y_test.index)
            label_map = list(le.classes_)
            print("Applied LabelEncoder for XGBoost training; saved mapping in memory.")
        except Exception as exc:
            print("Label encoding for XGBoost failed; proceeding without it:", exc)

    # If tuning is requested, split out a validation set from the training data
    if do_tune:
        if ts_col is not None:
            val_split = int(len(train_idx) * 0.8)
            x_train_sub, x_val = x_train.iloc[:val_split], x_train.iloc[val_split:]
            y_train_sub, y_val = y_train.iloc[:val_split], y_train.iloc[val_split:]
        else:
            x_train_sub, x_val, y_train_sub, y_val = train_test_split(
                x_train,
                y_train,
                test_size=0.2,
                random_state=42,
                stratify=y_train if y_train.nunique() > 1 else None,
            )
        try:
            import optuna

            study = optuna.create_study(direction="maximize")

            def _objective(trial):
                params = _suggest_params(trial, model_choice)
                clf = _get_classifier(model_choice, params)
                pipeline = Pipeline(
                    steps=[("preprocessor", preprocessor), ("classifier", clf)]
                )
                pipeline.fit(x_train_sub, y_train_sub)
                preds = pipeline.predict(x_val)
                return accuracy_score(y_val, preds)

            study.optimize(_objective, n_trials=optuna_trials)
            best_params = study.best_trial.params
            print(f"Optuna tuning complete. Best value: {study.best_value:.4f}")
            print(f"Best params: {best_params}")
            final_params = best_params
            # save optuna study params
            params_path = Path(str(model_path) + ".params.json")
            with open(params_path, "w", encoding="utf-8") as fh:
                json.dump(
                    {"best_value": study.best_value, "best_params": best_params},
                    fh,
                    indent=2,
                )
            print(f"Saved best params to {params_path}")
        except Exception as exc:
            print("Optuna tuning failed or not available:", exc)
            final_params = _default_params(model_choice)
    else:
        final_params = _default_params(model_choice)

    classifier = _get_classifier(model_choice, final_params)
    # For XGBoost, ensure the estimator's `classes_` matches the labels present
    if model_choice == "xgb":
        try:
            all_labels = np.unique(np.asarray(pd.concat([y_train, y_test])))
            classifier.classes_ = all_labels
        except Exception:
            pass

    model = Pipeline(steps=[("preprocessor", preprocessor), ("classifier", classifier)])

    # Try to fit; for XGBoost we attempt an intelligent fallback when small/odd label sets cause failures
    used_label_encoder = None
    try:
        model.fit(x_train, y_train)
        predictions = model.predict(x_test)
        score = accuracy_score(y_test, predictions) * 100
    except Exception as exc:
        print("Model fit failed:", exc)
        if model_choice == "xgb":
            try:
                from sklearn.preprocessing import LabelEncoder

                le = LabelEncoder()
                le.fit(pd.concat([y_train, y_test]))
                y_train_enc = pd.Series(le.transform(y_train), index=y_train.index)
                y_test_enc = pd.Series(le.transform(y_test), index=y_test.index)
                # recreate classifier and pipeline with encoded labels
                classifier = _get_classifier(model_choice, final_params)
                # ensure classes_ matches encoded labels
                try:
                    classifier.classes_ = np.arange(len(le.classes_))
                except Exception:
                    pass
                model = Pipeline(
                    steps=[("preprocessor", preprocessor), ("classifier", classifier)]
                )
                model.fit(x_train, y_train_enc)
                predictions = model.predict(x_test)
                # predictions are encoded labels; compute score against encoded y_test
                score = accuracy_score(y_test_enc, predictions) * 100
                used_label_encoder = le
                print("XGBoost trained with LabelEncoder fallback")
            except Exception as exc2:
                print("XGBoost fallback training failed:", exc2)
                # final fallback: train a RandomForest (robust)
                print(
                    "Falling back to RandomForest to ensure a model artifact is produced."
                )
                classifier = _get_classifier("rf", _default_params("rf"))
                model = Pipeline(
                    steps=[("preprocessor", preprocessor), ("classifier", classifier)]
                )
                model.fit(x_train, y_train)
                predictions = model.predict(x_test)
                score = accuracy_score(y_test, predictions) * 100
        else:
            raise
    print(f"Model ({model_choice}) Accuracy: {score:.2f}%")
    print(f"Training rows: {len(x_train)} | Test rows: {len(x_test)}")
    print(f"Features used: {', '.join(FEATURE_COLUMNS)}")

    # Try to compute and export feature importances for interpretability
    try:
        preprocessor = model.named_steps.get("preprocessor")
        classifier = model.named_steps.get("classifier")
        cat_names = []
        if preprocessor is not None:
            try:
                ohe = preprocessor.named_transformers_.get("categorical")
                if hasattr(ohe, "get_feature_names_out"):
                    cat_names = ohe.get_feature_names_out(CATEGORICAL_FEATURES).tolist()
            except Exception:
                cat_names = []

        feature_names = list(cat_names) + NUMERIC_FEATURES
        try:
            importances = getattr(classifier, "feature_importances_", None)
            if importances is None and hasattr(classifier, "booster"):
                # xgboost native booster
                try:
                    importances = classifier.get_booster().get_score(
                        importance_type="weight"
                    )
                    # get_score returns dict mapping feature names to importance
                    importance_map = {k: float(v) for k, v in importances.items()}
                except Exception:
                    importances = None

            if importances is not None and not isinstance(importances, dict):
                importances = importances.tolist()
                importance_map = {
                    name: float(imp)
                    for name, imp in zip(
                        feature_names, importances[: len(feature_names)]
                    )
                }

            importances_path = Path(str(model_path) + ".importances.json")
            with open(importances_path, "w", encoding="utf-8") as fh:
                json.dump(importance_map, fh, indent=2)
            print(f"Feature importances saved to {importances_path}")
        except Exception as exc:
            print("Failed to compute/save feature importances:", exc)
    except Exception:
        # Non-fatal: continue to persist the model
        pass

    # Optional MLflow logging (enabled if MLFLOW_TRACKING_URI present)
    mlflow_uri = os.getenv("MLFLOW_TRACKING_URI", "").strip()
    if mlflow_uri:
        try:
            import mlflow
            import mlflow.sklearn

            mlflow.set_tracking_uri(mlflow_uri)
            mlflow.set_experiment(os.getenv("MLFLOW_EXPERIMENT_NAME", "smart-commuter"))
            with mlflow.start_run():
                mlflow.log_metric("accuracy", float(score))
                mlflow.sklearn.log_model(model, "crowd_model")
            print("Logged model and metrics to MLflow")
        except Exception as exc:
            print("MLflow logging skipped:", exc)

    joblib.dump(model, model_path)
    print(f"Model saved: {model_path}")
    # Save label mapping if used (for consumers to decode predictions)
    if label_map is not None:
        try:
            label_map_path = Path(str(model_path) + ".label_map.json")
            with open(label_map_path, "w", encoding="utf-8") as fh:
                json.dump({"classes": label_map}, fh, indent=2)
            print(f"Label mapping saved to {label_map_path}")
        except Exception as exc:
            print("Failed to save label mapping:", exc)
    # If we used a LabelEncoder fallback when training XGBoost, save that mapping too
    if "used_label_encoder" in locals() and used_label_encoder is not None:
        try:
            le_path = Path(str(model_path) + ".label_map_le.json")
            with open(le_path, "w", encoding="utf-8") as fh:
                json.dump(
                    {"classes": used_label_encoder.classes_.tolist()}, fh, indent=2
                )
            print(f"Saved LabelEncoder classes to {le_path}")
        except Exception as exc:
            print("Failed to save LabelEncoder mapping:", exc)


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
    parser.add_argument(
        "--model",
        choices=["rf", "lgbm", "xgb"],
        default=None,
        help="Model backend to use (rf, lgbm, xgb). Can also be set with SCA_MODEL env var.",
    )
    parser.add_argument(
        "--tune",
        action="store_true",
        help="Run Optuna hyperparameter tuning (also enable with SCA_TUNE=true).",
    )
    parser.add_argument(
        "--trials",
        type=int,
        default=None,
        help="Number of Optuna trials (SCA_TRIALS env var used if omitted).",
    )
    args = parser.parse_args()

    data_file = args.input
    model_file = args.output
    train(
        data_file,
        model_file,
        model_choice=args.model,
        do_tune=args.tune,
        optuna_trials=args.trials,
    )
