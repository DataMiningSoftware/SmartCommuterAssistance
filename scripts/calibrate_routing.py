"""Fit the routing cost weights from real trip feedback.

The router is Dijkstra with three tunable costs:

    cost = travel_minutes
         + transfer_penalty   (per line change)
         + crowd_penalty      (per boarding, keyed by forecast level)
         + walk_minutes       (distance / pace)

None of those constants are learned today. This script fits them against
`trip_feedback` (predicted vs actual) and `route_choice` (agent path vs the
path the rider actually took), then writes the result to
app/assets/data/routing_weights.json so the app picks it up on next launch.

Usage
-----
    cd scripts
    python calibrate_routing.py                # fit and write
    python calibrate_routing.py --dry-run      # report only
    python calibrate_routing.py --synthetic    # ignore Supabase, use generated data

Requires SUPABASE_URL and SUPABASE_SERVICE_KEY for the real path. Without
them it falls back to synthetic data and says so in the output.
"""

from __future__ import annotations

import argparse
import json
import os
import random
from dataclasses import dataclass, asdict, field
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[1]
OUTPUT = REPO_ROOT / "app" / "assets" / "data" / "routing_weights.json"

DEFAULTS = {
    "transfer_penalty_fastest": 4,
    "transfer_penalty_balanced": 8,
    "transfer_penalty_comfort": 16,
    "walk_meters_per_minute": 80,
    "crowd_penalty_light": 1,
    "crowd_penalty_moderate": 2,
    "crowd_penalty_heavy": 4,
    "crowd_penalty_crowded": 6,
}


@dataclass
class TripSample:
    predicted_minutes: float
    actual_minutes: float
    walk_meters: float = 0.0
    transfers: int = 0
    crowd_level: int = 0


@dataclass
class ChoiceSample:
    agent_minutes: float
    agent_transfers: int
    chosen_minutes: float
    chosen_transfers: int


@dataclass
class Calibration:
    walk_pace: float = 80.0
    transfer_penalty: int = 8
    crowd_weights: dict = field(default_factory=dict)
    sample_size: int = 0
    mae_before: float = 0.0
    mae_after: float = 0.0


def _client():
    url = os.getenv("SUPABASE_URL")
    key = os.getenv("SUPABASE_SERVICE_KEY")
    if not url or not key:
        return None
    try:
        from supabase import create_client
    except ImportError:
        print("supabase-py not installed; falling back to synthetic data")
        return None
    return create_client(url, key)


def load_trip_samples(client) -> list[TripSample]:
    rows = (
        client.table("trip_feedback")
        .select(
            "predicted_minutes,actual_minutes,walk_distance_m,"
            "crowd_at_start,delays_reported"
        )
        .limit(5000)
        .execute()
        .data
        or []
    )
    samples: list[TripSample] = []
    for row in rows:
        predicted = row.get("predicted_minutes")
        actual = row.get("actual_minutes")
        if predicted is None or actual is None:
            continue
        samples.append(
            TripSample(
                predicted_minutes=float(predicted),
                actual_minutes=float(actual),
                walk_meters=float(row.get("walk_distance_m") or 0.0),
                crowd_level=int(row.get("crowd_at_start") or 0),
            )
        )
    return samples


def load_choice_samples(client) -> list[ChoiceSample]:
    rows = (
        client.table("route_choice")
        .select(
            "agent_predicted_min,chosen_minutes,agent_path,chosen_path,mode"
        )
        .limit(5000)
        .execute()
        .data
        or []
    )
    samples: list[ChoiceSample] = []
    for row in rows:
        agent_min = row.get("agent_predicted_min")
        chosen_min = row.get("chosen_minutes")
        if agent_min is None or chosen_min is None:
            continue
        samples.append(
            ChoiceSample(
                agent_minutes=float(agent_min),
                agent_transfers=_count_transfers(row.get("agent_path")),
                chosen_minutes=float(chosen_min),
                chosen_transfers=_count_transfers(row.get("chosen_path")),
            )
        )
    return samples


def _count_transfers(raw_path) -> int:
    if not raw_path:
        return 0
    try:
        path = json.loads(raw_path) if isinstance(raw_path, str) else raw_path
    except (TypeError, ValueError):
        return 0
    if not isinstance(path, list) or len(path) < 2:
        return 0
    return max(0, len(path) - 2)


def synthetic_trips(count: int = 400, seed: int = 7) -> list[TripSample]:
    """Plausible trips so the pipeline can be exercised before deploy."""
    rng = random.Random(seed)
    samples: list[TripSample] = []
    for _ in range(count):
        transfers = rng.choice([0, 0, 1, 1, 2])
        crowd = rng.choice([0, 1, 2, 3, 4, 5])
        walk = rng.choice([0.0, 0.0, 250.0, 700.0, 1200.0])
        base = rng.uniform(6, 45)
        true_pace = 78.0
        true_transfer = 9.0
        crowd_cost = {2: 1.2, 3: 2.6, 4: 4.8, 5: 7.0}.get(crowd, 0.0)
        actual = (
            base
            + transfers * true_transfer
            + crowd_cost
            + walk / true_pace
            + rng.gauss(0, 1.4)
        )
        samples.append(
            TripSample(
                predicted_minutes=base + transfers * 8 + crowd_cost,
                actual_minutes=max(1.0, actual),
                walk_meters=walk,
                transfers=transfers,
                crowd_level=crowd,
            )
        )
    return samples


def synthetic_choices(count: int = 200, seed: int = 11) -> list[ChoiceSample]:
    rng = random.Random(seed)
    samples: list[ChoiceSample] = []
    for _ in range(count):
        agent_transfers = rng.choice([1, 2, 3])
        chosen_transfers = max(0, agent_transfers - rng.choice([0, 1]))
        agent = rng.uniform(12, 40)
        chosen = agent + (agent_transfers - chosen_transfers) * 6 + rng.gauss(0, 2)
        samples.append(
            ChoiceSample(
                agent_minutes=agent,
                agent_transfers=agent_transfers,
                chosen_minutes=max(1.0, chosen),
                chosen_transfers=chosen_transfers,
            )
        )
    return samples


def mae(samples: list[TripSample], weights: dict) -> float:
    if not samples:
        return 0.0
    total = 0.0
    for sample in samples:
        predicted = (
            sample.predicted_minutes
            + sample.transfers * (weights["transfer_penalty_balanced"] - 8)
            + _crowd_cost(sample.crowd_level, weights)
            + sample.walk_meters / weights["walk_meters_per_minute"]
        )
        total += abs(predicted - sample.actual_minutes)
    return total / len(samples)


def _crowd_cost(level: int, weights: dict) -> float:
    return {
        2: weights["crowd_penalty_light"],
        3: weights["crowd_penalty_moderate"],
        4: weights["crowd_penalty_heavy"],
        5: weights["crowd_penalty_crowded"],
    }.get(level, 0.0)


def fit(trips: list[TripSample], choices: list[ChoiceSample]) -> Calibration:
    weights = dict(DEFAULTS)
    before = mae(trips, weights)

    best_pace = weights["walk_meters_per_minute"]
    best_score = before
    for pace in range(55, 106, 1):
        weights["walk_meters_per_minute"] = pace
        score = mae(trips, weights)
        if score < best_score:
            best_score, best_pace = score, pace
    weights["walk_meters_per_minute"] = best_pace

    for key, levels in (
        ("crowd_penalty_light", (2,)),
        ("crowd_penalty_moderate", (3,)),
        ("crowd_penalty_heavy", (4,)),
        ("crowd_penalty_crowded", (5,)),
    ):
        best_value = weights[key]
        best_score = mae(trips, weights)
        for value in range(0, 13):
            weights[key] = value
            score = mae(trips, weights)
            if score < best_score:
                best_score, best_value = score, value
        weights[key] = best_value

    transfer = weights["transfer_penalty_balanced"]
    if choices:
        best_value = transfer
        best_agreement = -1.0
        for value in range(0, 25):
            agreement = 0
            for sample in choices:
                agent_cost = sample.agent_minutes + sample.agent_transfers * value
                chosen_cost = (
                    sample.chosen_minutes + sample.chosen_transfers * value
                )
                if chosen_cost <= agent_cost:
                    agreement += 1
            ratio = agreement / len(choices)
            if ratio > best_agreement:
                best_agreement, best_value = ratio, value
        transfer = best_value

    weights["transfer_penalty_balanced"] = transfer
    weights["transfer_penalty_fastest"] = max(0, round(transfer / 2))
    weights["transfer_penalty_comfort"] = transfer * 2

    after = mae(trips, weights)
    return Calibration(
        walk_pace=float(weights["walk_meters_per_minute"]),
        transfer_penalty=int(transfer),
        crowd_weights={
            "crowd_penalty_light": weights["crowd_penalty_light"],
            "crowd_penalty_moderate": weights["crowd_penalty_moderate"],
            "crowd_penalty_heavy": weights["crowd_penalty_heavy"],
            "crowd_penalty_crowded": weights["crowd_penalty_crowded"],
        },
        sample_size=len(trips),
        mae_before=before,
        mae_after=after,
    )


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--synthetic", action="store_true")
    args = parser.parse_args()

    client = None if args.synthetic else _client()
    trips: list[TripSample] = []
    choices: list[ChoiceSample] = []
    source = "synthetic"

    if client is not None:
        trips = load_trip_samples(client)
        choices = load_choice_samples(client)
        if trips:
            source = "supabase"

    if not trips:
        trips = synthetic_trips()
        choices = synthetic_choices()

    result = fit(trips, choices)

    print(f"source        : {source}")
    print(f"samples       : {result.sample_size}")
    print(f"walk pace     : {result.walk_pace:.0f} m/min")
    print(f"transfer cost : {result.transfer_penalty} min")
    print(f"crowd weights : {result.crowd_weights}")
    print(f"MAE before    : {result.mae_before:.2f} min")
    print(f"MAE after     : {result.mae_after:.2f} min")

    payload = {
        **DEFAULTS,
        "transfer_penalty_balanced": result.transfer_penalty,
        "transfer_penalty_fastest": max(0, result.transfer_penalty // 2),
        "transfer_penalty_comfort": result.transfer_penalty * 2,
        "walk_meters_per_minute": result.walk_pace,
        **result.crowd_weights,
        "source": source,
        "sample_size": result.sample_size,
        "mae_minutes": round(result.mae_after, 2),
    }

    if args.dry_run:
        print("\ndry run — not writing")
        print(json.dumps(payload, indent=2))
        return

    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    OUTPUT.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
    print(f"\nwrote {OUTPUT}")


if __name__ == "__main__":
    main()
