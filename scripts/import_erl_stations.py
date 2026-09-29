from __future__ import annotations

import argparse
import csv
import json
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
NETWORK_PATH = REPO / "app" / "assets" / "data" / "transit_network.json"
LAYOUT_PATH = REPO / "app" / "assets" / "schematic_layout.json"
SEQUENCES_PATH = REPO / "app" / "assets" / "data" / "line_sequences.json"
SEGMENT_TIMES_PATH = REPO / "app" / "assets" / "data" / "segment_times.json"
STOPS_CSV = REPO / "scripts" / "train_stops_kl.csv"

ERL_SEGMENT_MINUTES = {
    "ER6": {"KJ15|KLIA": 28, "KLIA|KLIA2": 3},
    "ER7": {
        "KJ15|SP15": 7,
        "SP15|PY41": 12,
        "PY41|SALAK_TINGGI": 10,
        "SALAK_TINGGI|KLIA": 7,
        "KLIA|KLIA2": 3,
    },
}

ERL_LINES = {
    "ER6": ["KJ15", "KLIA", "KLIA2"],
    "ER7": ["KJ15", "SP15", "PY41", "SALAK_TINGGI", "KLIA", "KLIA2"],
}
LINE_TO_SCHEMATIC = {"ER6": "6", "ER7": "7"}
COORDS = {
    "SALAK_TINGGI": (2.825397, 101.7130747),
    "KLIA": (2.7547334, 101.7046397),
    "KLIA2": (2.7445265, 101.6851796),
}
RENAMES = {"KLIA": "KLIA T1", "KLIA2": "KLIA T2"}
SHORT_NAMES = {"ER6": "KLIA Ekspres", "ER7": "KLIA Transit"}
LONG_NAMES = {"ER6": "ERL KLIA Ekspres", "ER7": "ERL KLIA Transit"}


def apply_network(data: dict) -> dict:
    stations = {s["id"]: s for s in data["stations"]}
    updated_coords = []
    for station in stations.values():
        station["lines"] = [line for line in station["lines"] if line not in ERL_LINES]
    for line, ids in ERL_LINES.items():
        for sid in ids:
            station = stations.get(sid)
            if station is None:
                raise SystemExit(f"Missing ERL station {sid} in transit_network.json")
            if line not in station["lines"]:
                station["lines"].append(line)
    for sid, name in RENAMES.items():
        if sid in stations:
            stations[sid]["name"] = name
    for sid, (lat, lon) in COORDS.items():
        if sid in stations:
            stations[sid]["lat"] = lat
            stations[sid]["lng"] = lon
            updated_coords.append(sid)
    return {"updated_coords": updated_coords}


def apply_layout(data: dict, network: dict) -> dict:
    network_stations = {s["id"]: s for s in network["stations"]}
    layout_stations = data["stations"]
    for entry in layout_stations.values():
        entry["lines"] = [
            line for line in entry["lines"] if line not in LINE_TO_SCHEMATIC.values()
        ]
    added = []
    for line, ids in ERL_LINES.items():
        schematic = LINE_TO_SCHEMATIC[line]
        for sid in ids:
            if sid not in layout_stations:
                station = network_stations[sid]
                layout_stations[sid] = {
                    "name": station["name"],
                    "x": 0.0,
                    "y": 0.0,
                    "lines": [],
                }
                added.append(sid)
            entry = layout_stations[sid]
            if schematic not in entry["lines"]:
                entry["lines"].append(schematic)
    return {"added": added}


def apply_sequences(sequences: dict) -> dict:
    for line, ids in ERL_LINES.items():
        sequences[line] = ids
    return sequences


def apply_csv(network: dict) -> dict:
    network_stations = {s["id"]: s for s in network["stations"]}
    with STOPS_CSV.open("r", encoding="utf-8-sig", newline="") as fh:
        rows = list(csv.DictReader(fh))
    fieldnames = list(rows[0].keys())
    rows = [row for row in rows if row["route_id"] not in ERL_LINES]

    max_count = max(int(float(row["count"])) for row in rows)
    appended = 0
    for line, ids in ERL_LINES.items():
        for seq, sid in enumerate(ids, start=1):
            station = network_stations[sid]
            max_count += 1
            rows.append(
                {
                    "stop_id": sid,
                    "stop_name": station["name"],
                    "stop_lat": f"{station['lat']}",
                    "stop_lon": f"{station['lng']}",
                    "route_id": line,
                    "category": "ERL",
                    "count": str(max_count),
                    "sequence_order": str(seq),
                    "is_interchange": str(len(station["lines"]) > 1).lower(),
                }
            )
            appended += 1

    with STOPS_CSV.open("w", encoding="utf-8", newline="") as fh:
        writer = csv.DictWriter(fh, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(rows)
    return {"appended": appended}


def main() -> None:
    parser = argparse.ArgumentParser(description="Add ERL KLIA Ekspres/Transit stations to the catalog.")
    parser.add_argument("--write", action="store_true", help="Apply changes (default is a dry run)")
    args = parser.parse_args()

    network = json.loads(NETWORK_PATH.read_text(encoding="utf-8"))
    layout = json.loads(LAYOUT_PATH.read_text(encoding="utf-8"))
    sequences = json.loads(SEQUENCES_PATH.read_text(encoding="utf-8"))

    network_report = apply_network(network)
    layout_report = apply_layout(layout, network)
    apply_sequences(sequences)

    print("ERL coords updated:", network_report["updated_coords"])
    print("layout added:", layout_report["added"])
    print("ER6:", " -> ".join(ERL_LINES["ER6"]))
    print("ER7:", " -> ".join(ERL_LINES["ER7"]))

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
    segments = (
        json.loads(SEGMENT_TIMES_PATH.read_text(encoding="utf-8"))
        if SEGMENT_TIMES_PATH.exists()
        else {}
    )
    for line, pairs in ERL_SEGMENT_MINUTES.items():
        target = segments.setdefault(line, {})
        for key, minutes in pairs.items():
            target[key] = minutes
            target["|".join(reversed(key.split("|")))] = minutes
    SEGMENT_TIMES_PATH.write_text(
        json.dumps(segments, indent=2, ensure_ascii=False) + "\n", encoding="utf-8"
    )
    csv_report = apply_csv(network)
    print("csv rows appended:", csv_report["appended"])
    print("wrote:", NETWORK_PATH.name, LAYOUT_PATH.name, SEQUENCES_PATH.name, STOPS_CSV.name)


if __name__ == "__main__":
    main()
