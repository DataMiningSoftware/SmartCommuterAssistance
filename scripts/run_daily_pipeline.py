from __future__ import annotations

import os
import subprocess
import sys
from datetime import datetime, time
from pathlib import Path
from zoneinfo import ZoneInfo

KL_TZ = ZoneInfo("Asia/Kuala_Lumpur")
SCRIPT_DIR = Path(__file__).resolve().parent
TRAIN_SCRIPT = SCRIPT_DIR / "train_crowd_model.py"
PREDICT_SCRIPT = SCRIPT_DIR / "predict_and_upsert_crowd.py"
AGGREGATE_SCRIPT = SCRIPT_DIR / "aggregate_training_data.py"
GENERATE_SCRIPT = SCRIPT_DIR / "generate_crowd_data.py"
TRAINING_DATA = SCRIPT_DIR / "real_training_data.csv"
SIMULATED_DATA = SCRIPT_DIR / "simulated_crowd_data.csv"
MODEL_OUTPUT = SCRIPT_DIR / "crowd_predictor.pkl"


def _env() -> dict[str, str]:
    return {
        **os.environ,
        "SUPABASE_URL": os.getenv("SUPABASE_URL", ""),
        "SUPABASE_SERVICE_KEY": os.getenv("SUPABASE_SERVICE_KEY", ""),
        "SCA_MODEL": "rf",
    }


def step(name: str) -> None:
    print(f"\n{'=' * 60}")
    print(f"  [{datetime.now(tz=KL_TZ).isoformat()}] {name}")
    print(f"{'=' * 60}")


def run(args: list[str], env: dict[str, str] | None = None) -> None:
    result = subprocess.run(
        [sys.executable] + args,
        cwd=SCRIPT_DIR,
        env=env or _env(),
        capture_output=False,
        text=True,
    )
    if result.returncode != 0:
        print(f"  FAILED (exit code {result.returncode})")
        if result.stderr:
            print(f"  stderr: {result.stderr.strip()}")
        sys.exit(result.returncode)


def main() -> None:
    now = datetime.now(tz=KL_TZ)
    print(f"Daily pipeline starting at {now.isoformat()}")
    print(f"Scripts dir: {SCRIPT_DIR}")

    step("1/3 — Aggregating real training data from Supabase")
    agg_env = _env()
    run([str(AGGREGATE_SCRIPT)], env=agg_env)

    data_path = TRAINING_DATA if TRAINING_DATA.exists() else SIMULATED_DATA
    if not data_path.exists():
        step("1b/3 — No real or simulated data found; generating simulated data")
        run([str(GENERATE_SCRIPT), "--rows", "10000"], env=_env())
        data_path = SIMULATED_DATA

    if not data_path.exists():
        print("  Failed to produce training data. Aborting.")
        sys.exit(1)

    step(f"2/3 — Training model on {data_path.name}")
    train_env = _env()
    train_args = [
        str(TRAIN_SCRIPT),
        "--input",
        str(data_path),
        "--output",
        str(MODEL_OUTPUT),
        "--model",
        "rf",
    ]
    run(train_args, env=train_env)

    step(f"3/3 — Predicting and upserting forecasts to Supabase")
    predict_env = _env()
    run([str(PREDICT_SCRIPT)], env=predict_env)

    print(f"\nPipeline complete at {datetime.now(tz=KL_TZ).isoformat()}")


if __name__ == "__main__":
    main()
