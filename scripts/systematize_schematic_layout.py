from __future__ import annotations

import json
import math
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
NETWORK_PATH = REPO / "app" / "assets" / "data" / "transit_network.json"
LAYOUT_PATH = REPO / "app" / "assets" / "schematic_layout.json"
SEQUENCES_PATH = REPO / "app" / "assets" / "data" / "line_sequences.json"

NEW_LINES = {"1": "KT1", "2": "KT2", "6": "ER6", "7": "ER7"}
GRID = 0.5


def _positions(layout: dict) -> dict[str, list[float]]:
    return {
        sid: [station["x"], station["y"]]
        for sid, station in layout["stations"].items()
    }


def _hub_ids(layout: dict) -> set[str]:
    return {
        sid
        for sid, station in layout["stations"].items()
        if len(station.get("lines", [])) > 1
    }


def _anchor_runs(chain: list[str], hubs: set[str]) -> list[tuple[int, int]]:
    indices = [i for i, sid in enumerate(chain) if sid in hubs]
    if not indices:
        return []
    runs = []
    if indices[0] > 0:
        runs.append((0, indices[0]))
    for left, right in zip(indices, indices[1:]):
        runs.append((left, right))
    if indices[-1] < len(chain) - 1:
        runs.append((indices[-1], len(chain) - 1))
    return runs


def _route_run(positions: dict, start: str, end: str, mids: list[str]) -> None:
    if start not in positions or end not in positions:
        return
    ax, ay = positions[start]
    bx, by = positions[end]
    dx, dy = bx - ax, by - ay
    n = len(mids)
    if n == 0:
        return

    if abs(dx) < 0.4:
        for k, sid in enumerate(mids):
            positions[sid] = [ax, ay + dy * (k + 1) / (n + 1)]
        return
    if abs(dy) < 0.4:
        for k, sid in enumerate(mids):
            positions[sid] = [ax + dx * (k + 1) / (n + 1), ay]
        return

    if abs(dx) >= abs(dy):
        leg_x, leg_y = abs(dx), abs(dy)
        n_x = min(n, max(1, round(n * leg_x / (leg_x + leg_y)))) if n > 1 else 1
        n_y = n - n_x
        for k in range(n_x):
            positions[mids[k]] = [ax + dx * (k + 1) / (n_x + 1), ay]
        for k in range(n_y):
            positions[mids[n_x + k]] = [bx, ay + dy * (k + 1) / (n_y + 1)]
    else:
        leg_x, leg_y = abs(dx), abs(dy)
        n_y = min(n, max(1, round(n * leg_y / (leg_x + leg_y)))) if n > 1 else 1
        n_x = n - n_y
        for k in range(n_y):
            positions[mids[k]] = [ax, ay + dy * (k + 1) / (n_y + 1)]
        for k in range(n_x):
            positions[mids[n_y + k]] = [ax + dx * (k + 1) / (n_x + 1), by]


def main() -> None:
    network = json.loads(NETWORK_PATH.read_text(encoding="utf-8"))
    layout = json.loads(LAYOUT_PATH.read_text(encoding="utf-8"))
    sequences = json.loads(SEQUENCES_PATH.read_text(encoding="utf-8"))

    positions = _positions(layout)
    hubs = _hub_ids(layout)

    moved = 0
    for _, sequence_key in NEW_LINES.items():
        chain = [sid for sid in sequences.get(sequence_key, []) if sid in positions]
        if len(chain) < 3:
            continue
        for left, right in _anchor_runs(chain, hubs):
            start, end = chain[left], chain[right]
            mids = chain[left + 1 : right]
            if not mids:
                continue
            _route_run(positions, start, end, mids)
            moved += len(mids)

    for sid, (x, y) in positions.items():
        layout["stations"][sid]["x"] = round(x / GRID) * GRID
        layout["stations"][sid]["y"] = round(y / GRID) * GRID

    for station in network["stations"]:
        layout_station = layout["stations"].get(station["id"])
        if layout_station is not None:
            station["gridX"] = layout_station["x"]
            station["gridY"] = layout_station["y"]

    LAYOUT_PATH.write_text(
        json.dumps(layout, indent=2, ensure_ascii=False) + "\n", encoding="utf-8"
    )
    NETWORK_PATH.write_text(
        json.dumps(network, indent=2, ensure_ascii=False) + "\n", encoding="utf-8"
    )
    print(f"rerouted stations: {moved}, hubs fixed: {len(hubs)}")


if __name__ == "__main__":
    main()
