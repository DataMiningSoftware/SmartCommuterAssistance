from __future__ import annotations

import json
from pathlib import Path

import matplotlib.pyplot as plt
import pandas as pd
from sklearn.compose import ColumnTransformer
from sklearn.ensemble import RandomForestClassifier
from sklearn.metrics import ConfusionMatrixDisplay, accuracy_score
from sklearn.model_selection import train_test_split
from sklearn.pipeline import Pipeline
from sklearn.preprocessing import OneHotEncoder

from train_crowd_model import (
    CATEGORICAL_FEATURES,
    FEATURE_COLUMNS,
    NUMERIC_FEATURES,
    _ensure_feature_columns,
)


def main() -> None:
    script_dir = Path(__file__).resolve().parent
    repo_root = script_dir.parent
    output_dir = repo_root / "app" / "report_assets" / "classification_graphs"
    output_dir.mkdir(parents=True, exist_ok=True)

    data_path = script_dir / "simulated_crowd_data.csv"
    rf_importance_path = script_dir / "crowd_predictor.pkl.importances.json"
    lgbm_importance_path = (
        script_dir / "crowd_predictor_lgbm_optuna10.pkl.importances.json"
    )
    lgbm_params_path = script_dir / "crowd_predictor_lgbm_optuna10.pkl.params.json"

    df = _ensure_feature_columns(pd.read_csv(data_path))
    y = pd.to_numeric(df["occupancy_level"], errors="coerce").fillna(0).astype(int)
    x = df[FEATURE_COLUMNS]

    x_train, x_test, y_train, y_test = train_test_split(
        x,
        y,
        test_size=0.2,
        random_state=42,
        stratify=y if y.value_counts().min() >= 2 else None,
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
                    n_jobs=-1,
                ),
            ),
        ]
    )
    model.fit(x_train, y_train)
    y_pred = model.predict(x_test)
    rf_accuracy = accuracy_score(y_test, y_pred) * 100

    lgbm_best_value = None
    if lgbm_params_path.exists():
        with lgbm_params_path.open("r", encoding="utf-8") as fh:
            lgbm_best_value = json.load(fh).get("best_value")

    _plot_model_accuracy(
        output_dir / "model_accuracy_comparison.png",
        rf_accuracy=rf_accuracy,
        lgbm_accuracy=(lgbm_best_value * 100) if lgbm_best_value is not None else None,
    )
    _plot_feature_importance(
        rf_importance_path,
        output_dir / "rf_feature_importance_top12.png",
        title="Random Forest Feature Importance",
        top_n=12,
        aggregate_one_hot=True,
    )
    _plot_feature_importance(
        lgbm_importance_path,
        output_dir / "lgbm_feature_importance_top12.png",
        title="LightGBM Feature Importance",
        top_n=12,
        aggregate_one_hot=True,
    )
    _plot_class_distribution(
        df=df,
        output_path=output_dir / "class_distribution.png",
    )
    _plot_confusion_matrix(
        y_test=y_test,
        y_pred=y_pred,
        output_path=output_dir / "rf_confusion_matrix.png",
    )
    _plot_occupancy_by_hour(
        df=df,
        output_path=output_dir / "occupancy_by_hour.png",
    )

    print(f"Saved graphs to {output_dir}")


def _plot_model_accuracy(
    output_path: Path,
    rf_accuracy: float,
    lgbm_accuracy: float | None,
) -> None:
    labels = ["Random Forest", "LightGBM + Optuna"]
    values = [rf_accuracy, lgbm_accuracy or 0.0]
    colors = ["#0A3A8B", "#D7263D"]

    fig, ax = plt.subplots(figsize=(8, 5))
    bars = ax.bar(labels, values, color=colors, width=0.55)
    ax.set_ylim(0, max(values) + 10)
    ax.set_ylabel("Accuracy (%)")
    ax.set_title("Crowd Classification Accuracy Comparison")
    ax.grid(axis="y", linestyle="--", alpha=0.25)
    for index, bar in enumerate(bars):
        label = (
            "N/A" if index == 1 and lgbm_accuracy is None else f"{values[index]:.2f}%"
        )
        ax.text(
            bar.get_x() + bar.get_width() / 2,
            bar.get_height() + 0.8,
            label,
            ha="center",
            va="bottom",
            fontweight="bold",
        )
    if lgbm_accuracy is None:
        ax.text(
            0.5,
            0.02,
            "LightGBM metric missing in local environment. Use committed Optuna artifact if available.",
            transform=ax.transAxes,
            ha="center",
            va="bottom",
            fontsize=9,
            color="#667085",
        )
    fig.tight_layout()
    fig.savefig(output_path, dpi=200, bbox_inches="tight")
    plt.close(fig)


def _plot_feature_importance(
    json_path: Path,
    output_path: Path,
    title: str,
    top_n: int,
    aggregate_one_hot: bool,
) -> None:
    with json_path.open("r", encoding="utf-8") as fh:
        raw = json.load(fh)

    series = pd.Series({str(key): float(value) for key, value in raw.items()})
    if aggregate_one_hot:
        series = _aggregate_encoded_feature_importance(series)
    top = series.sort_values(ascending=True).tail(top_n)

    fig, ax = plt.subplots(figsize=(9, 6))
    ax.barh(top.index, top.values, color="#0A3A8B")
    ax.set_title(title)
    ax.set_xlabel("Importance")
    ax.grid(axis="x", linestyle="--", alpha=0.25)
    fig.tight_layout()
    fig.savefig(output_path, dpi=200, bbox_inches="tight")
    plt.close(fig)


def _aggregate_encoded_feature_importance(series: pd.Series) -> pd.Series:
    grouped: dict[str, float] = {}
    for key, value in series.items():
        if key.startswith("stop_id_"):
            grouped["stop_id"] = grouped.get("stop_id", 0.0) + value
        elif key.startswith("route_id_"):
            grouped["route_id"] = grouped.get("route_id", 0.0) + value
        else:
            grouped[key] = grouped.get(key, 0.0) + value
    return pd.Series(grouped)


def _plot_class_distribution(df: pd.DataFrame, output_path: Path) -> None:
    counts = (
        pd.to_numeric(df["occupancy_level"], errors="coerce")
        .fillna(0)
        .astype(int)
        .value_counts()
        .sort_index()
    )
    fig, ax = plt.subplots(figsize=(8, 5))
    bars = ax.bar(counts.index.astype(str), counts.values, color="#F4B400")
    ax.set_title("Crowd Class Distribution")
    ax.set_xlabel("Occupancy Level")
    ax.set_ylabel("Sample Count")
    ax.grid(axis="y", linestyle="--", alpha=0.25)
    for bar, value in zip(bars, counts.values):
        ax.text(
            bar.get_x() + bar.get_width() / 2,
            bar.get_height() + 30,
            str(int(value)),
            ha="center",
            va="bottom",
            fontweight="bold",
        )
    fig.tight_layout()
    fig.savefig(output_path, dpi=200, bbox_inches="tight")
    plt.close(fig)


def _plot_confusion_matrix(
    y_test: pd.Series,
    y_pred,
    output_path: Path,
) -> None:
    fig, ax = plt.subplots(figsize=(6.5, 6))
    labels = sorted(set(y_test.tolist()) | set(int(v) for v in y_pred))
    ConfusionMatrixDisplay.from_predictions(
        y_test,
        y_pred,
        display_labels=labels,
        cmap="Blues",
        ax=ax,
        colorbar=False,
    )
    ax.set_title("Random Forest Confusion Matrix")
    fig.tight_layout()
    fig.savefig(output_path, dpi=200, bbox_inches="tight")
    plt.close(fig)


def _plot_occupancy_by_hour(df: pd.DataFrame, output_path: Path) -> None:
    scoped = df.copy()
    scoped["hour"] = (
        pd.to_numeric(scoped["hour"], errors="coerce").fillna(0).astype(int)
    )
    scoped["occupancy_level"] = (
        pd.to_numeric(scoped["occupancy_level"], errors="coerce").fillna(0).astype(int)
    )
    pivot = (
        scoped.groupby(["hour", "occupancy_level"])
        .size()
        .unstack(fill_value=0)
        .sort_index()
    )
    fig, ax = plt.subplots(figsize=(10, 5.5))
    for level in pivot.columns:
        ax.plot(
            pivot.index, pivot[level], marker="o", linewidth=2, label=f"Level {level}"
        )
    ax.set_title("Occupancy Level Distribution by Hour")
    ax.set_xlabel("Hour of Day")
    ax.set_ylabel("Sample Count")
    ax.set_xticks(range(0, 24, 2))
    ax.grid(True, linestyle="--", alpha=0.25)
    ax.legend()
    fig.tight_layout()
    fig.savefig(output_path, dpi=200, bbox_inches="tight")
    plt.close(fig)


if __name__ == "__main__":
    main()
