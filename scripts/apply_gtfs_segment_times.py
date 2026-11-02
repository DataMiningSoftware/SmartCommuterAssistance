"""Replace estimated edge times with real GTFS inter-station times.

The network ships with a flat 2-minute guess for most Rapid KL segments.
The official rapid-rail-kl GTFS feed has per-stop arrival times, so the real
median time between consecutive stops can be computed per direction.

Pipeline
--------
1. download the feed (or accept --gtfs-dir for an extracted copy)
2. group stop_times by trip, order by stop_sequence
3. median delta between consecutive stops, per (route, from, to)
4. map GTFS route ids onto the app's line ids
5. write the minutes back into transit_network.json

Run:  python scripts/apply_gtfs_segment_times.py
      python scripts/apply_gtfs_segment_times.py --gtfs-dir <path> --dry-run
"""

from __future__ import annotations

import argparse
import csv
import io
import json
import statistics
import urllib.request
import zipfile
from collections import defaultdict
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[1]
NETWORK = REPO_ROOT / "app" / "assets" / "data" / "transit_network.json"

FEED_URL = "https://api.data.gov.my/gtfs-static/prasarana?category=rapid-rail-kl"

ROUTE_MAP = {
    "AG": "AG",
    "KJ": "KJ",
    "PH": "SP",
    "KGL": "KG",
    "PYL": "PY",
}

MAX_PLAUSIBLE_SECONDS = 1200


def parse_time(raw: str) -> int | None:
    parts = raw.strip().split(":")
    if len(parts) != 3:
        return None
    try:
        hours, minutes, seconds = (int(p) for p in parts)
    except ValueError:
        return None
    return hours * 3600 + minutes * 60 + seconds


def read_feed(gtfs_dir: Path | None) -> dict[str, bytes]:
    if gtfs_dir is not None:
        return {
            name: (gtfs_dir / name).read_bytes()
            for name in ("trips.txt", "stop_times.txt")
        }

    with urllib.request.urlopen(FEED_URL, timeout=120) as response:
        payload = response.read()
    files: dict[str, bytes] = {}
    with zipfile.ZipFile(io.BytesIO(payload)) as archive:
        for name in ("trips.txt", "stop_times.txt"):
            files[name] = archive.read(name)
    return files


def decode(raw: bytes) -> str:
    return raw.decode("utf-8-sig", errors="ignore")


def compute_segment_times(
    files: dict[str, bytes],
) -> dict[tuple[str, str, str], int]:
    trip_route: dict[str, str] = {}
    for row in csv.DictReader(io.StringIO(decode(files["trips.txt"]))):
        route = ROUTE_MAP.get(row["route_id"].strip())
        if route is None:
            continue
        trip_route[row["trip_id"].strip()] = route

    per_trip: dict[str, list[tuple[int, str, int]]] = defaultdict(list)
    for row in csv.DictReader(io.StringIO(decode(files["stop_times.txt"]))):
        trip = row["trip_id"].strip()
        if trip not in trip_route:
            continue
        seconds = parse_time(row["arrival_time"])
        if seconds is None:
            seconds = parse_time(row["departure_time"])
        if seconds is None:
            continue
        try:
            sequence = int(row["stop_sequence"])
        except ValueError:
            continue
        per_trip[trip].append((sequence, row["stop_id"].strip(), seconds))

    samples: dict[tuple[str, str, str], list[int]] = defaultdict(list)
    for trip, stops in per_trip.items():
        stops.sort()
        route = trip_route[trip]
        for (_, a_id, a_time), (_, b_id, b_time) in zip(stops, stops[1:]):
            delta = b_time - a_time
            if delta <= 0 or delta > MAX_PLAUSIBLE_SECONDS:
                continue
            samples[(route, a_id, b_id)].append(delta)

    return {
        key: max(1, round(statistics.median(values) / 60))
        for key, values in samples.items()
        if values
    }


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--gtfs-dir", type=Path, default=None)
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()

    files = read_feed(args.gtfs_dir)
    segment_minutes = compute_segment_times(files)
    print(f"segments from GTFS: {len(segment_minutes)}")

    data = json.loads(NETWORK.read_text(encoding="utf-8"))
    updated = 0
    before_by_line: dict[str, list[int]] = defaultdict(list)
    after_by_line: dict[str, list[int]] = defaultdict(list)
    missing = 0

    for connection in data["connections"]:
        line = connection["route"]
        if line not in ROUTE_MAP.values():
            continue
        before_by_line[line].append(connection["minutes"])
        key = (line, connection["from"], connection["to"])
        minutes = segment_minutes.get(key)
        if minutes is None:
            missing += 1
            after_by_line[line].append(connection["minutes"])
            continue
        if minutes != connection["minutes"]:
            updated += 1
        connection["minutes"] = minutes
        after_by_line[line].append(minutes)

    print(f"edges updated     : {updated}")
    print(f"edges left as-is  : {missing}")
    print("\nline   before -> after (avg minutes)")
    for line in sorted(before_by_line):
        before = statistics.mean(before_by_line[line])
        after = statistics.mean(after_by_line[line])
        print(f"  {line:<4} {before:5.2f} -> {after:5.2f}")

    if args.dry_run:
        print("\ndry run — not writing")
        return

    NETWORK.write_text(
        json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    print(f"\nwrote {NETWORK}")


if __name__ == "__main__":
    main()
