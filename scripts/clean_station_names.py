from __future__ import annotations

import csv
import json
import re
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
NETWORK_PATH = REPO / "app" / "assets" / "data" / "transit_network.json"
LAYOUT_PATH = REPO / "app" / "assets" / "schematic_layout.json"
STOPS_CSV = REPO / "scripts" / "train_stops_kl.csv"
APP_CSV = REPO / "app" / "assets" / "train_stops_kl.csv"

SUFFIXES = r"(REDONE|UOB|CBP COOPBANK PERTAMA|THE FACE STYLE|MAYBANK)"


def clean_station_name(raw: str) -> str:
    name = raw.strip()
    name = re.sub(r"\([^)]*\)", "", name).strip()
    name = re.sub(r"^BANK RAKYAT\s+", "", name, flags=re.I)
    name = re.sub(r"^CGC\s+", "", name, flags=re.I)
    name = re.sub(rf"\s*-\s*{SUFFIXES}\s*$", "", name, flags=re.I).strip()
    name = name.replace("SOUTH QUAY-USJ", "SOUTH QUAY - USJ")
    name = name.replace("SUNWAY-SETIA", "SUNWAY - SETIA")
    name = name.replace("Sunway-Setia", "Sunway - Setia")
    name = re.sub(r"KENTOMEN\b", "KENTONMEN", name)
    name = re.sub(r"\s+", " ", name).strip()
    return name


def main() -> None:
    network = json.loads(NETWORK_PATH.read_text(encoding="utf-8"))
    changed = []
    for station in network["stations"]:
        cleaned = clean_station_name(station["name"])
        if cleaned != station["name"]:
            changed.append((station["id"], station["name"], cleaned))
            station["name"] = cleaned
    NETWORK_PATH.write_text(
        json.dumps(network, indent=2, ensure_ascii=False) + "\n", encoding="utf-8"
    )

    layout = json.loads(LAYOUT_PATH.read_text(encoding="utf-8"))
    for station in layout["stations"].values():
        if "name" in station:
            station["name"] = clean_station_name(station["name"])
    LAYOUT_PATH.write_text(
        json.dumps(layout, indent=2, ensure_ascii=False) + "\n", encoding="utf-8"
    )

    with STOPS_CSV.open("r", encoding="utf-8-sig", newline="") as fh:
        reader = csv.DictReader(fh)
        fieldnames = list(reader.fieldnames or [])
        rows = list(reader)
    for row in rows:
        row["stop_name"] = clean_station_name(row["stop_name"])
    with STOPS_CSV.open("w", encoding="utf-8", newline="") as fh:
        writer = csv.DictWriter(fh, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(rows)

    with APP_CSV.open("w", encoding="utf-8", newline="") as fh:
        writer = csv.writer(fh)
        writer.writerow(["stop_id", "stop_name", "route_id", "stop_lat", "stop_lon"])
        for row in rows:
            writer.writerow(
                [
                    row["stop_id"],
                    row["stop_name"].replace(",", " "),
                    row["route_id"],
                    row["stop_lat"],
                    row["stop_lon"],
                ]
            )

    print(f"renamed stations: {len(changed)}")
    for station_id, before, after in changed:
        print(f"  {station_id}: '{before}' -> '{after}'")


if __name__ == "__main__":
    main()
