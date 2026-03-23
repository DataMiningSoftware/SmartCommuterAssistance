from __future__ import annotations

import random
from pathlib import Path

import pandas as pd


def generate(rows: int = 10_000) -> pd.DataFrame:
    data: list[list[int]] = []
    for _ in range(rows):
        hour = random.randint(6, 23)
        is_weekend = random.choice([0, 1])
        is_raining = random.choice([0, 1])

        if is_weekend == 0 and (7 <= hour <= 9 or 17 <= hour <= 19):
            base_crowd = random.randint(70, 100)
        else:
            base_crowd = random.randint(10, 50)

        if is_raining:
            base_crowd += random.randint(10, 20)

        occupancy_percent = min(base_crowd, 100)
        if occupancy_percent < 30:
            level = 0
        elif occupancy_percent < 60:
            level = 1
        elif occupancy_percent < 85:
            level = 2
        else:
            level = 3

        data.append([hour, is_weekend, is_raining, level])

    return pd.DataFrame(
        data,
        columns=["hour", "is_weekend", "is_raining", "occupancy_level"],
    )


if __name__ == "__main__":
    script_dir = Path(__file__).resolve().parent
    output_path = script_dir / "simulated_crowd_data.csv"
    df = generate()
    df.to_csv(output_path, index=False)
    print(f"Data generated: {output_path}")
