from __future__ import annotations

import argparse
import csv
import json
import os
from collections import defaultdict
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
STOPS_CSV = REPO / "scripts" / "train_stops_kl.csv"
SEGMENT_TIMES = REPO / "app" / "assets" / "data" / "segment_times.json"
ENV_FILE = REPO / "backend" / ".env"
BATCH_SIZE = 500


def load_env() -> tuple[str, str]:
    url = os.getenv("SUPABASE_URL", "").strip()
    key = os.getenv("SUPABASE_SERVICE_KEY", "").strip()
    if (not url or not key) and ENV_FILE.exists():
        for line in ENV_FILE.read_text(encoding="utf-8").splitlines():
            line = line.strip()
            if not line or line.startswith("#") or "=" not in line:
                continue
            name, value = line.split("=", 1)
            name = name.strip()
            value = value.strip().strip('"').strip("'")
            if name == "SUPABASE_URL" and not url:
                url = value
            elif name == "SUPABASE_SERVICE_KEY" and not key:
                key = value
    return url, key


def load_rows() -> list[dict]:
    with STOPS_CSV.open("r", encoding="utf-8-sig", newline="") as fh:
        return list(csv.DictReader(fh))


def dedupe_stops(rows: list[dict]) -> list[dict]:
    seen: dict[str, dict] = {}
    for row in rows:
        stop_id = row["stop_id"].strip().upper()
        if stop_id and stop_id not in seen:
            seen[stop_id] = row
    return list(seen.values())


def connection_rows(rows: list[dict]) -> list[dict]:
    segments = (
        json.loads(SEGMENT_TIMES.read_text(encoding="utf-8"))
        if SEGMENT_TIMES.exists()
        else {}
    )
    by_route: dict[str, list[dict]] = defaultdict(list)
    by_name: dict[str, list[str]] = defaultdict(list)
    for row in rows:
        stop_id = row["stop_id"].strip().upper()
        route_id = (row["route_id"] or "").strip().upper()
        if not stop_id or not route_id:
            continue
        by_route[route_id].append(row)
        by_name[(row["stop_name"] or "").strip().upper()].append(stop_id)

    connections: dict[tuple, dict] = {}
    for route_id, route_rows in by_route.items():
        ordered = sorted(route_rows, key=lambda r: (int(float(r["sequence_order"] or 0)), r["stop_id"]))
        for left, right in zip(ordered, ordered[1:]):
            a = left["stop_id"].strip().upper()
            b = right["stop_id"].strip().upper()
            if a == b:
                continue
            minutes = segments.get(route_id, {}).get(f"{a}|{b}", 2)
            for source, target in ((a, b), (b, a)):
                connections[(source, target, route_id, "standard_stop")] = {
                    "from_stop_id": source,
                    "to_stop_id": target,
                    "route_id": route_id,
                    "connection_type": "standard_stop",
                    "travel_time_minutes": int(minutes),
                }

    for name, stop_ids in by_name.items():
        unique = sorted(set(stop_ids))
        if len(unique) < 2:
            continue
        for index, left in enumerate(unique[:-1]):
            for right in unique[index + 1:]:
                for source, target in ((left, right), (right, left)):
                    connections[(source, target, "INTERCHANGE", "interchange_transfer")] = {
                        "from_stop_id": source,
                        "to_stop_id": target,
                        "route_id": "INTERCHANGE",
                        "connection_type": "interchange_transfer",
                        "travel_time_minutes": 3,
                    }
    return list(connections.values())


def upsert_batches(client, table: str, rows: list[dict], on_conflict: str) -> int:
    total = 0
    for start in range(0, len(rows), BATCH_SIZE):
        batch = rows[start:start + BATCH_SIZE]
        client.table(table).upsert(batch, on_conflict=on_conflict).execute()
        total += len(batch)
    return total


def replace_table(client, table: str, rows: list[dict], filter_column: str) -> int:
    client.table(table).delete().neq(filter_column, "__keep__").execute()
    total = 0
    for start in range(0, len(rows), BATCH_SIZE):
        batch = rows[start:start + BATCH_SIZE]
        client.table(table).insert(batch).execute()
        total += len(batch)
    return total


def main() -> None:
    parser = argparse.ArgumentParser(description="Upsert the station catalog and connections into Supabase.")
    parser.add_argument("--write", action="store_true", help="Apply changes (default is a dry run)")
    args = parser.parse_args()

    url, key = load_env()
    if not url or not key:
        raise SystemExit("Set SUPABASE_URL and SUPABASE_SERVICE_KEY (env or backend/.env).")

    rows = load_rows()
    stops = dedupe_stops(rows)
    connections = connection_rows(rows)

    print(f"csv rows: {len(rows)}")
    print(f"unique stations: {len(stops)}")
    print(f"connections (incl. interchanges): {len(connections)}")

    if not args.write:
        print("dry run — pass --write to upsert into Supabase")
        return

    from supabase import create_client

    client = create_client(url, key)
    stops_done = upsert_batches(client, "train_stops_kl", [r for r in stops], "stop_id")
    try:
        connections_done = upsert_batches(
            client,
            "route_connections",
            connections,
            "from_stop_id,to_stop_id,route_id,connection_type",
        )
        mode = "upserted"
    except Exception as error:
        if "ON CONFLICT" not in str(error):
            raise
        connections_done = replace_table(
            client, "route_connections", connections, "route_id"
        )
        mode = "replaced"
    print(f"upserted train_stops_kl: {stops_done}")
    print(f"{mode} route_connections: {connections_done}")


if __name__ == "__main__":
    main()
