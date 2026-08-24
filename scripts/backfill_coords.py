import csv
import io
import json
import os
import re
import zipfile

BASE = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "app")
JSON_PATH = os.path.join(BASE, "assets", "data", "transit_network.json")
GTFS_ZIP = os.path.join(
    os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
    "backend",
    "data",
    "gtfs",
    "rapid-rail-kl.zip",
)
STOPS_CSV = os.path.join(
    os.path.dirname(os.path.abspath(__file__)), "train_stops_kl.csv"
)
ASSET_CSV = os.path.join(BASE, "assets", "train_stops_kl.csv")


def norm_id(value):
    s = (value or "").strip().upper()
    s = re.sub(r"\s+", "", s)
    return s


def norm_id_loose(value):
    s = norm_id(value)
    return re.sub(r"^([A-Z]+)0+(?=\d)", r"\1", s)


def norm_name(value):
    s = (value or "").strip().upper()
    s = re.sub(r"\([^)]*\)", "", s)
    s = re.sub(r"^BANK RAKYAT\s+", "", s)
    s = re.sub(r"^CGC\s+", "", s)
    s = re.sub(r"\s*-\s*(REDONE|UOB|CBP COOPBANK PERTAMA|THE FACE STYLE|MAYBANK)\s*$", "", s)
    s = re.sub(r"\s*-\s*", " ", s)
    s = re.sub(r"([A-Z])(\d)", r"\1 \2", s)
    s = re.sub(r"(\d)([A-Z])", r"\1 \2", s)
    s = re.sub(r"\s+", " ", s)
    return s.strip()


def load_lookup():
    lookup = {"id": {}, "id_loose": {}, "name": {}}
    sources = []

    if os.path.exists(GTFS_ZIP):
        z = zipfile.ZipFile(GTFS_ZIP)
        rows = list(csv.DictReader(io.StringIO(z.read("stops.txt").decode("utf-8-sig"))))
        sources.append(("gtfs", rows))
    if os.path.exists(STOPS_CSV):
        rows = list(csv.DictReader(open(STOPS_CSV, encoding="utf-8-sig")))
        sources.append(("scripts_csv", rows))
    if os.path.exists(ASSET_CSV):
        rows = list(csv.DictReader(open(ASSET_CSV, encoding="utf-8-sig")))
        sources.append(("asset_csv", rows))

    for src, rows in sources:
        for r in rows:
            if src == "gtfs":
                sid = r.get("stop_id", "")
                sname = r.get("stop_name", "")
                lat = float(r.get("stop_lat") or 0)
                lng = float(r.get("stop_lon") or 0)
            elif src == "scripts_csv":
                sid = r.get("stop_id", "")
                sname = r.get("stop_name", "")
                lat = float(r.get("stop_lat") or 0)
                lng = float(r.get("stop_lon") or 0)
            else:
                sid = r.get("station_id", "")
                sname = r.get("station_name", "")
                lat = float(r.get("latitude") or 0)
                lng = float(r.get("longitude") or 0)

            if lat == 0 and lng == 0:
                continue
            lookup["id"][norm_id(sid)] = (lat, lng)
            lookup["id_loose"][norm_id_loose(sid)] = (lat, lng)
            lookup["name"][norm_name(sname)] = (lat, lng)

    return lookup


def main():
    lookup = load_lookup()
    with open(JSON_PATH, "r", encoding="utf-8") as f:
        data = json.load(f)

    filled = 0
    unmatched = []
    for s in data["stations"]:
        if s.get("lat") != 0 or s.get("lng") != 0:
            continue
        sid = s["id"]
        coord = None
        for key in (norm_id(sid), norm_id_loose(sid)):
            if key in lookup["id"] or key in lookup["id_loose"]:
                coord = lookup["id"].get(key) or lookup["id_loose"].get(key)
                break
        if coord is None:
            coord = lookup["name"].get(norm_name(s["name"]))
        if coord is not None:
            s["lat"], s["lng"] = coord
            filled += 1
        else:
            unmatched.append((s["id"], s["name"]))

    with open(JSON_PATH, "w", encoding="utf-8") as f:
        json.dump(data, f, indent=2)

    still_zero = sum(1 for s in data["stations"] if s["lat"] == 0 and s["lng"] == 0)
    print(f"Filled {filled} stations with coordinates.")
    print(f"Remaining zero-coord: {still_zero}/{len(data['stations'])}")
    if unmatched:
        print("\nUnmatched (no source found):")
        for sid, name in sorted(unmatched):
            print(f"  {sid:24s} {name}")


if __name__ == "__main__":
    main()
