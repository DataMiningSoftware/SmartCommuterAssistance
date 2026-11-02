"""Repair missing segments in transit_network.json.

Several lines have stations but no edge between consecutive stops, which makes
the router detour onto other lines. Station ids encode the order along a line
(PY01, PY02, ...), so the missing links can be rebuilt deterministically.

For each repairable line:
  * collect stations whose id matches <LINE><number>
  * sort by that number
  * add a bidirectional edge for any consecutive pair that lacks one
  * estimate the travel time from the great-circle distance

Run:  python scripts/repair_line_topology.py [--dry-run]
"""

from __future__ import annotations

import argparse
import json
import math
import re
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[1]
NETWORK = REPO_ROOT / "app" / "assets" / "data" / "transit_network.json"

REPAIRABLE = ["AG", "SP", "PY", "KG", "MR", "KJ", "BRT"]

ID_PATTERN = re.compile(r"^(AG|SP|PY|KG|MR|KJ|BRT)(\d+)([A-Z]?)$")

KM_PER_MINUTE = 0.55
MIN_MINUTES = 2
MAX_MINUTES = 8


def haversine_km(lat1: float, lon1: float, lat2: float, lon2: float) -> float:
    radius = 6371.0
    d_lat = math.radians(lat2 - lat1)
    d_lon = math.radians(lon2 - lon1)
    a = (
        math.sin(d_lat / 2) ** 2
        + math.cos(math.radians(lat1))
        * math.cos(math.radians(lat2))
        * math.sin(d_lon / 2) ** 2
    )
    return 2 * radius * math.atan2(math.sqrt(a), math.sqrt(1 - a))


def travel_minutes(a: dict, b: dict) -> int:
    km = haversine_km(a["lat"], a["lng"], b["lat"], b["lng"])
    minutes = round(km / KM_PER_MINUTE)
    return max(MIN_MINUTES, min(MAX_MINUTES, minutes))


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()

    data = json.loads(NETWORK.read_text(encoding="utf-8"))
    stations = {s["id"]: s for s in data["stations"]}
    connections = data["connections"]

    def has_edge(source: str, target: str, line: str) -> bool:
        return any(
            c["from"] == source and c["to"] == target and c["route"] == line
            for c in connections
        )

    added: list[str] = []
    by_line: dict[str, list[tuple[tuple[int, str], str]]] = {}

    for station in data["stations"]:
        match = ID_PATTERN.match(station["id"])
        if not match:
            continue
        line = match.group(1)
        number = (int(match.group(2)), match.group(3) or "")
        if line not in REPAIRABLE:
            continue
        by_line.setdefault(line, []).append((number, station["id"]))

    for line, entries in sorted(by_line.items()):
        entries.sort()
        for (_, a_id), (_, b_id) in zip(entries, entries[1:]):
            if has_edge(a_id, b_id, line):
                continue
            a = stations[a_id]
            b = stations[b_id]
            minutes = travel_minutes(a, b)
            connections.append(
                {
                    "from": a_id,
                    "to": b_id,
                    "minutes": minutes,
                    "type": "standard_stop",
                    "route": line,
                }
            )
            connections.append(
                {
                    "from": b_id,
                    "to": a_id,
                    "minutes": minutes,
                    "type": "standard_stop",
                    "route": line,
                }
            )
            added.append(f"{line}: {a_id} <-> {b_id} ({minutes}m)")

    orphaned = [
        s["id"]
        for s in data["stations"]
        if not any(c["from"] == s["id"] for c in connections)
    ]
    kept = [s for s in data["stations"] if s["id"] not in set(orphaned)]
    removed = [s["id"] for s in data["stations"] if s["id"] in set(orphaned)]
    data["stations"] = kept

    print(f"added segments : {len(added)}")
    for item in added:
        print(f"  + {item}")
    print(f"orphaned removed: {removed}")

    if args.dry_run:
        print("\ndry run — not writing")
        return

    NETWORK.write_text(
        json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    print(f"\nwrote {NETWORK}")


if __name__ == "__main__":
    main()
