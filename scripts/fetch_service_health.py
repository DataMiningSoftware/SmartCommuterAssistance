from __future__ import annotations

import csv
import io
import os
import urllib.request
import zipfile
from collections import defaultdict
from datetime import datetime, timedelta, timezone
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
KTMB_CACHE = REPO / "backend" / "data" / "gtfs" / "ktmb.zip"
RT_URL = "https://api.data.gov.my/gtfs-realtime/vehicle-position/ktmb"
STATIC_URL = "https://api.data.gov.my/gtfs-static/ktmb"
MALAYSIA_TZ = timezone(timedelta(hours=8), name="MYT")
ROUTE_LINES = {"KC05_KB18": "KT1", "KA15_KD19": "KT2"}
MAX_SANE_DELAY_MIN = 120


def fetch_bytes(url: str) -> bytes:
    request = urllib.request.Request(
        url,
        headers={"User-Agent": "SmartCommuterAssistant/1.0"},
    )
    with urllib.request.urlopen(request, timeout=60) as response:
        return response.read()


def ensure_static_zip() -> None:
    if KTMB_CACHE.exists():
        age = datetime.now() - datetime.fromtimestamp(KTMB_CACHE.stat().st_mtime)
        if age < timedelta(hours=24):
            return
    KTMB_CACHE.parent.mkdir(parents=True, exist_ok=True)
    KTMB_CACHE.write_bytes(fetch_bytes(STATIC_URL))


def _rows(archive: zipfile.ZipFile, name: str) -> list[dict]:
    try:
        raw = archive.open(name)
    except KeyError:
        return []
    with raw:
        return list(csv.DictReader(io.TextIOWrapper(raw, encoding="utf-8-sig")))


def _secs(value: str) -> int:
    parts = (value or "").strip().split(":")
    if len(parts) < 2:
        return 0
    seconds = int(parts[0]) * 3600 + int(parts[1]) * 60
    if len(parts) > 2:
        seconds += int(parts[2])
    return seconds


def load_static_trips() -> dict[str, tuple[str, str, list[dict]]]:
    with zipfile.ZipFile(KTMB_CACHE) as archive:
        trips_raw = _rows(archive, "trips.txt")
        stops_raw = _rows(archive, "stops.txt")
        times_raw = _rows(archive, "stop_times.txt")

    stop_names = {
        row["stop_id"].strip(): row.get("stop_name", "").strip()
        for row in stops_raw
    }
    trips: dict[str, tuple[str, str]] = {}
    for row in trips_raw:
        line = ROUTE_LINES.get((row.get("route_id") or "").strip().upper())
        if line is None:
            continue
        trips[row["trip_id"].strip()] = line

    times_by_trip: dict[str, list[dict]] = defaultdict(list)
    for row in times_raw:
        trip_id = (row.get("trip_id") or "").strip()
        if trip_id not in trips:
            continue
        times_by_trip[trip_id].append(
            {
                "stop_id": (row.get("stop_id") or "").strip(),
                "arrival": _secs(row.get("arrival_time", "")),
                "seq": int(row.get("stop_sequence") or 0),
            }
        )

    result: dict[str, tuple[str, str, list[dict]]] = {}
    for trip_id, line in trips.items():
        ordered = sorted(times_by_trip.get(trip_id, []), key=lambda t: t["seq"])
        if not ordered:
            continue
        terminal = stop_names.get(ordered[-1]["stop_id"], "")
        result[trip_id] = (line, terminal, ordered)
    return result


def load_realtime_trip_ids() -> list[str]:
    try:
        from google.transit import gtfs_realtime_pb2
    except ImportError:
        print("  gtfs-realtime-bindings not installed; skipping")
        return []

    feed = gtfs_realtime_pb2.FeedMessage()
    feed.ParseFromString(fetch_bytes(RT_URL))
    trip_ids: list[str] = []
    for entity in feed.entity:
        if not entity.HasField("vehicle"):
            continue
        trip_id = entity.vehicle.trip.trip_id.strip()
        if trip_id:
            trip_ids.append(trip_id)
    return trip_ids


def match_trip(trip_id: str, trips: dict) -> str | None:
    if trip_id in trips:
        return trip_id
    for candidate in trips:
        if candidate.endswith(trip_id) or trip_id.endswith(candidate):
            return candidate
    return None


def build_health_rows() -> list[dict]:
    ensure_static_zip()
    trips = load_static_trips()
    if not trips:
        return []

    now = datetime.now(MALAYSIA_TZ)
    now_secs = now.hour * 3600 + now.minute * 60 + now.second
    counts: dict[tuple[str, str], int] = defaultdict(int)
    delays: dict[tuple[str, str], list[int]] = defaultdict(list)

    for trip_id in load_realtime_trip_ids():
        matched = match_trip(trip_id, trips)
        if matched is None:
            continue
        line, terminal, times = trips[matched]
        key = (line, terminal)
        counts[key] += 1
        upcoming = [t for t in times if t["arrival"] >= now_secs]
        if not upcoming:
            continue
        delay = max(0, (now_secs - upcoming[0]["arrival"]) // 60)
        if delay <= MAX_SANE_DELAY_MIN:
            delays[key].append(delay)

    rows = []
    for key, count in counts.items():
        values = delays.get(key, [])
        avg = round(sum(values) / len(values), 1) if values else 0.0
        rows.append(
            {
                "line_id": key[0],
                "direction": key[1],
                "avg_delay_min": avg,
                "vehicle_count": count,
                "updated_at": now.isoformat(),
            }
        )
    return rows


def upsert(rows: list[dict]) -> None:
    url = os.getenv("SUPABASE_URL", "").strip()
    key = os.getenv("SUPABASE_SERVICE_KEY", "").strip()
    if not url or not key:
        print("  SUPABASE_URL / SUPABASE_SERVICE_KEY not set; skipped upsert")
        return
    try:
        from supabase import create_client
    except ImportError:
        print("  supabase package not installed; skipped upsert")
        return
    client = create_client(url, key)
    try:
        client.table("service_health").upsert(
            rows, on_conflict="line_id,direction"
        ).execute()
        print(f"  Upserted {len(rows)} service_health rows")
    except Exception as error:
        print(f"  Upsert failed (run migration_service_health.sql?): {error}")


def main() -> None:
    rows = build_health_rows()
    print(f"Computed {len(rows)} service health rows from KTMB realtime")
    for row in rows:
        print(
            f"  {row['line_id']} -> {row['direction']}: "
            f"{row['avg_delay_min']} min avg, {row['vehicle_count']} vehicles"
        )
    upsert(rows)


if __name__ == "__main__":
    main()
