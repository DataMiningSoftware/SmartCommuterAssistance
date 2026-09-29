from __future__ import annotations

import argparse
import collections
import csv
import io
import json
import urllib.request
import zipfile
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
FEED_PATH = REPO / "backend" / "data" / "gtfs" / "ktmb.zip"
FEED_URL = "https://api.data.gov.my/gtfs-static/ktmb"
NETWORK_PATH = REPO / "app" / "assets" / "data" / "transit_network.json"
LAYOUT_PATH = REPO / "app" / "assets" / "schematic_layout.json"
SEQUENCES_PATH = REPO / "app" / "assets" / "data" / "line_sequences.json"
STOP_MAP_PATH = REPO / "app" / "assets" / "data" / "ktmb_stop_map.json"
SEGMENT_TIMES_PATH = REPO / "app" / "assets" / "data" / "segment_times.json"
STOPS_CSV = REPO / "scripts" / "train_stops_kl.csv"

ROUTE_LINES = {"KC05_KB18": "KT1", "KA15_KD19": "KT2"}
LINE_TO_SCHEMATIC = {"KT1": "1", "KT2": "2"}
ERL_LINES = {"ER6", "ER7"}
SHARED_CORE = {"KUALA_LUMPUR", "BANK_NEGARA", "PUTRA"}

REMOVED_LINE = "KS"

GTFS_TO_STATION = {
    "25100": "PULAU_SEBANG",
    "23900": "REMBAU",
    "23100": "SUNGAI_GADUT",
    "22900": "SENAWANG",
    "22700": "SEREMBAN",
    "22400": "TIROI",
    "22000": "LABU",
    "21500": "NILAI",
    "21300": "BATANG_BENAR",
    "20900": "BANGI",
    "20500": "UKM",
    "20402": "KAJANG2",
    "20400": "KG35",
    "19900": "SERDANG",
    "19600": "SP15",
    "19400": "SALAK_SELATAN",
    "19300": "SEPUTEH",
    "19205": "MID_VALLEY",
    "19100": "KJ15",
    "19000": "KUALA_LUMPUR",
    "18900": "BANK_NEGARA",
    "18800": "PUTRA",
    "50000": "SENTUL",
    "50300": "BATU_KENTONMEN",
    "50400": "KAMPUNG_BATU",
    "50500": "TAMAN_WAHYU",
    "50600": "BATU_CAVES",
    "55200": "PELABUHAN_KLANG",
    "55100": "JALAN_KASTAM",
    "55000": "KAMPUNG_RAJA_UDA",
    "54900": "TELUK_GADONG",
    "54800": "TELUK_PULAI",
    "54700": "KLANG",
    "54500": "BUKIT_BADAK",
    "54400": "PADANG_JAWA",
    "54200": "SHAH_ALAM",
    "53800": "BATU_TIGA",
    "53700": "KJ28",
    "53600": "SETIA_JAYA",
    "53500": "SERI_SETIA",
    "53400": "KAMPUNG_DATO_HARUN",
    "53100": "JALAN_TEMPLER",
    "53000": "PETALING",
    "52900": "PANTAI_DALAM",
    "52800": "ANGKASAPURI",
    "52700": "KJ17",
    "18700": "SEGAMBUT",
    "18600": "KEPONG",
    "18400": "KEPONG_SENTRAL",
    "18500": "PY04",
    "18100": "KUANG",
    "17800": "RAWANG",
    "17300": "SERENDAH",
    "16500": "BATANG_KALI",
    "16300": "RASA",
    "16100": "KUALA_KUBU_BHARU",
    "15200": "TANJUNG_MALIM",
}

NEW_STATION_NAMES = {
    "SEPUTEH": "Seputeh",
    "SALAK_SELATAN": "Salak Selatan",
    "SENTUL": "Sentul",
    "BATU_KENTONMEN": "Batu Kentonmen",
    "KAMPUNG_BATU": "Kampung Batu",
    "SERI_SETIA": "Seri Setia",
    "KAMPUNG_DATO_HARUN": "Kampung Dato Harun",
    "JALAN_TEMPLER": "Jalan Templer",
    "PANTAI_DALAM": "Pantai Dalam",
    "ANGKASAPURI": "Angkasapuri",
}

RENAMES = {"KJ15": "KL SENTRAL", "MR1": "KL SENTRAL", "SETIA_JAYA": "Sunway-Setia Jaya"}
DROPPED_LINES = {"SETIA_JAYA": ["BRT"]}
LAYOUT_DROPPED_LINES = {"SETIA_JAYA": ["B1"]}


def load_feed() -> zipfile.ZipFile:
    if not FEED_PATH.exists():
        FEED_PATH.parent.mkdir(parents=True, exist_ok=True)
        data = urllib.request.urlopen(FEED_URL, timeout=120).read()
        FEED_PATH.write_bytes(data)
    return zipfile.ZipFile(FEED_PATH)


def read_rows(z: zipfile.ZipFile, name: str) -> list[dict]:
    return list(csv.DictReader(io.TextIOWrapper(z.open(name), encoding="utf-8-sig")))


def _parse_secs(value: str) -> int:
    parts = value.strip().split(":")
    if len(parts) < 2:
        return 0
    hours = int(parts[0]) * 3600
    minutes = int(parts[1]) * 60
    seconds = int(parts[2]) if len(parts) > 2 else 0
    return hours + minutes + seconds


def segment_times(z: zipfile.ZipFile) -> dict[str, dict[str, int]]:
    times = read_rows(z, "stop_times.txt")
    trips = read_rows(z, "trips.txt")
    route_by_trip = {
        row["trip_id"]: row["route_id"]
        for row in trips
        if row["route_id"] in ROUTE_LINES
    }
    by_trip = collections.defaultdict(list)
    for row in times:
        if row["trip_id"] in route_by_trip:
            by_trip[row["trip_id"]].append(row)

    samples: dict[str, dict[str, list[int]]] = {line: {} for line in ROUTE_LINES.values()}
    for trip_id, rows in by_trip.items():
        line = ROUTE_LINES[route_by_trip[trip_id]]
        rows.sort(key=lambda r: int(r["stop_sequence"]))
        for left, right in zip(rows, rows[1:]):
            a = GTFS_TO_STATION.get(left["stop_id"])
            b = GTFS_TO_STATION.get(right["stop_id"])
            if a is None or b is None:
                continue
            minutes = (
                _parse_secs(right["arrival_time"]) - _parse_secs(left["arrival_time"])
            ) // 60
            if minutes <= 0:
                continue
            samples[line].setdefault(f"{a}|{b}", []).append(minutes)

    result: dict[str, dict[str, int]] = {}
    for line, pairs in samples.items():
        result[line] = {}
        for key, values in pairs.items():
            values.sort()
            median = values[len(values) // 2]
            result[line][key] = median
            other = "|".join(reversed(key.split("|")))
            result[line].setdefault(other, median)
    return result


def ordered_route_stops(z: zipfile.ZipFile) -> dict[str, list[dict]]:
    stops = {r["stop_id"]: r for r in read_rows(z, "stops.txt")}
    trips = read_rows(z, "trips.txt")
    times = read_rows(z, "stop_times.txt")
    by_trip = collections.defaultdict(list)
    for row in times:
        by_trip[row["trip_id"]].append(row)

    result: dict[str, list[dict]] = {}
    for route_id, line in ROUTE_LINES.items():
        route_trips = [t for t in trips if t["route_id"] == route_id]
        if not route_trips:
            continue
        best = max(route_trips, key=lambda t: len(by_trip[t["trip_id"]]))
        seq = sorted(by_trip[best["trip_id"]], key=lambda r: int(r["stop_sequence"]))
        entries = []
        for row in seq:
            stop = stops[row["stop_id"]]
            entries.append(
                {
                    "gtfs_id": row["stop_id"],
                    "name": stop["stop_name"].strip(),
                    "lat": float(stop["stop_lat"]),
                    "lon": float(stop["stop_lon"]),
                    "sequence": int(row["stop_sequence"]),
                    "line": line,
                }
            )
        result[line] = entries
    return result


def line_sequences(route_stops: dict[str, list[dict]]) -> dict[str, list[str]]:
    sequences: dict[str, list[str]] = {}
    for line, entries in route_stops.items():
        ids: list[str] = []
        for entry in entries:
            station_id = GTFS_TO_STATION.get(entry["gtfs_id"])
            if station_id is None:
                raise SystemExit(f"No station mapping for GTFS stop {entry['gtfs_id']} ({entry['name']})")
            if station_id not in ids:
                ids.append(station_id)
        sequences[line] = ids
    return sequences


def apply_network(data: dict, route_stops: dict[str, list[dict]]) -> dict:
    stations = {s["id"]: s for s in data["stations"]}
    order = [s["id"] for s in data["stations"]]

    removed: list[str] = []
    for sid in list(order):
        station = stations[sid]
        drop = {"KT1", "KT2", REMOVED_LINE, *DROPPED_LINES.get(sid, [])}
        station["lines"] = [line for line in station["lines"] if line not in drop]

    added: list[str] = []
    updated_coords: list[str] = []
    for line, entries in route_stops.items():
        for entry in entries:
            sid = GTFS_TO_STATION[entry["gtfs_id"]]
            if sid not in stations:
                stations[sid] = {
                    "id": sid,
                    "name": NEW_STATION_NAMES.get(sid, entry["name"].title()),
                    "lat": round(entry["lat"], 6),
                    "lng": round(entry["lon"], 6),
                    "gridX": 0.0,
                    "gridY": 0.0,
                    "lines": [],
                }
                order.append(sid)
                added.append(sid)
            station = stations[sid]
            if line not in station["lines"]:
                station["lines"].append(line)
            if sid in NEW_STATION_NAMES:
                station["lat"] = round(entry["lat"], 6)
                station["lng"] = round(entry["lon"], 6)
                updated_coords.append(sid)
            elif station.get("lat", 0.0) == 0.0 and station.get("lng", 0.0) == 0.0:
                station["lat"] = round(entry["lat"], 6)
                station["lng"] = round(entry["lon"], 6)
                updated_coords.append(sid)

    for sid, station in stations.items():
        if sid in SHARED_CORE:
            for line in ("KT1", "KT2"):
                if line not in station["lines"]:
                    station["lines"].append(line)

    for sid, name in RENAMES.items():
        if sid in stations:
            stations[sid]["name"] = name

    kept = []
    for sid in order:
        station = stations[sid]
        if not station["lines"]:
            removed.append(sid)
            continue
        if station.get("lines") == [REMOVED_LINE]:
            removed.append(sid)
            continue
        kept.append(station)

    data["stations"] = kept
    return {"removed": removed, "added": added, "updated_coords": updated_coords}


def interpolate_positions(sequence: list[str], layout_stations: dict) -> dict[str, tuple]:
    known = {
        sid: (layout_stations[sid]["x"], layout_stations[sid]["y"])
        for sid in sequence
        if sid in layout_stations
    }
    positions: dict[str, tuple] = {}
    n = len(sequence)
    for index, sid in enumerate(sequence):
        if sid in known:
            positions[sid] = known[sid]
            continue
        prev_idx = next((i for i in range(index - 1, -1, -1) if sequence[i] in known), None)
        next_idx = next((i for i in range(index + 1, n) if sequence[i] in known), None)
        if prev_idx is not None and next_idx is not None:
            x0, y0 = known[sequence[prev_idx]]
            x1, y1 = known[sequence[next_idx]]
            t = (index - prev_idx) / (next_idx - prev_idx)
            positions[sid] = (
                round(x0 + (x1 - x0) * t, 1),
                round(y0 + (y1 - y0) * t, 1),
            )
        elif prev_idx is not None:
            base = known[sequence[prev_idx]]
            positions[sid] = (base[0], round(base[1] + 1.5 * (index - prev_idx), 1))
        elif next_idx is not None:
            base = known[sequence[next_idx]]
            positions[sid] = (base[0], round(base[1] - 1.5 * (next_idx - index), 1))
        else:
            positions[sid] = (0.0, 0.0)
    return positions


def apply_layout(data: dict, network: dict, sequences: dict[str, list[str]]) -> dict:
    network_stations = {s["id"]: s for s in network["stations"]}
    layout_stations = data["stations"]

    data["lines"].pop(REMOVED_LINE, None)

    for sid in list(layout_stations):
        station = layout_stations[sid]
        drop = {REMOVED_LINE, *LAYOUT_DROPPED_LINES.get(sid, [])}
        station["lines"] = [line for line in station["lines"] if line not in drop]
        if sid not in network_stations:
            del layout_stations[sid]

    for station in layout_stations.values():
        station["lines"] = [
            line for line in station["lines"] if line not in LINE_TO_SCHEMATIC.values()
        ]

    added: list[str] = []
    for line in ("KT1", "KT2"):
        schematic_line = LINE_TO_SCHEMATIC[line]
        sequence = sequences.get(line, [])
        positions = interpolate_positions(sequence, layout_stations)
        for sid in sequence:
            station = network_stations.get(sid)
            if station is None:
                continue
            if sid not in layout_stations:
                x, y = positions.get(sid, (0.0, 0.0))
                layout_stations[sid] = {
                    "name": station["name"],
                    "x": x,
                    "y": y,
                    "lines": [],
                }
                added.append(sid)
            entry = layout_stations[sid]
            if schematic_line not in entry["lines"]:
                entry["lines"].append(schematic_line)

    for sid in list(layout_stations):
        entry = layout_stations[sid]
        if not entry["lines"]:
            del layout_stations[sid]

    return {"added": added}


def apply_csv(route_stops: dict[str, list[dict]], network: dict) -> dict:
    network_stations = {s["id"]: s for s in network["stations"]}
    with STOPS_CSV.open("r", encoding="utf-8-sig", newline="") as fh:
        rows = list(csv.DictReader(fh))
    fieldnames = list(rows[0].keys())
    rows = [
        row
        for row in rows
        if not (row["route_id"] in ("KT1", "KT2") and row["category"] == "KTM")
    ]

    existing_ids = {row["stop_id"] for row in rows}
    for row in rows:
        if row["stop_id"] in RENAMES:
            row["stop_name"] = RENAMES[row["stop_id"]]

    max_count = max(int(float(row["count"])) for row in rows)
    appended = 0
    for line, entries in route_stops.items():
        for entry in entries:
            sid = GTFS_TO_STATION[entry["gtfs_id"]]
            station = network_stations[sid]
            max_count += 1
            rows.append(
                {
                    "stop_id": sid,
                    "stop_name": station["name"],
                    "stop_lat": f"{station['lat']}",
                    "stop_lon": f"{station['lng']}",
                    "route_id": line,
                    "category": "KTM",
                    "count": str(max_count),
                    "sequence_order": str(entry["sequence"]),
                    "is_interchange": str(len(station["lines"]) > 1).lower(),
                }
            )
            appended += 1

    with STOPS_CSV.open("w", encoding="utf-8", newline="") as fh:
        writer = csv.DictWriter(fh, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(rows)

    return {"appended": appended, "existing_ids": len(existing_ids)}


def main() -> None:
    parser = argparse.ArgumentParser(description="Import Klang Valley KTM Komuter stations from the KTMB GTFS feed.")
    parser.add_argument("--write", action="store_true", help="Apply changes (default is a dry run)")
    args = parser.parse_args()

    z = load_feed()
    route_stops = ordered_route_stops(z)
    sequences = line_sequences(route_stops)
    segments = segment_times(z)

    network = json.loads(NETWORK_PATH.read_text(encoding="utf-8"))
    layout = json.loads(LAYOUT_PATH.read_text(encoding="utf-8"))

    network_report = apply_network(network, route_stops)
    layout_report = apply_layout(layout, network, sequences)

    print("KT1 sequence:", " -> ".join(sequences.get("KT1", [])))
    print("KT2 sequence:", " -> ".join(sequences.get("KT2", [])))
    print("network added:", network_report["added"])
    print("network removed:", network_report["removed"])
    print("network coords updated:", network_report["updated_coords"])
    print("layout added:", layout_report["added"])
    print("station count:", len(network["stations"]))

    if not args.write:
        print("dry run — pass --write to apply")
        return

    NETWORK_PATH.write_text(
        json.dumps(network, indent=2, ensure_ascii=False) + "\n", encoding="utf-8"
    )
    LAYOUT_PATH.write_text(
        json.dumps(layout, indent=2, ensure_ascii=False) + "\n", encoding="utf-8"
    )
    SEQUENCES_PATH.write_text(
        json.dumps(sequences, indent=2, ensure_ascii=False) + "\n", encoding="utf-8"
    )
    STOP_MAP_PATH.write_text(
        json.dumps(GTFS_TO_STATION, indent=2, ensure_ascii=False) + "\n",
        encoding="utf-8",
    )
    existing = (
        json.loads(SEGMENT_TIMES_PATH.read_text(encoding="utf-8"))
        if SEGMENT_TIMES_PATH.exists()
        else {}
    )
    existing.update(segments)
    SEGMENT_TIMES_PATH.write_text(
        json.dumps(existing, indent=2, ensure_ascii=False) + "\n", encoding="utf-8"
    )
    csv_report = apply_csv(route_stops, network)
    print("csv rows appended:", csv_report["appended"])
    print("wrote:", NETWORK_PATH.name, LAYOUT_PATH.name, SEQUENCES_PATH.name, STOPS_CSV.name)


if __name__ == "__main__":
    main()
