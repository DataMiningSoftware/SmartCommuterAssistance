import json, csv, os, re

base = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "app")
json_path = os.path.join(base, "assets", "data", "transit_network.json")
csv_path = os.path.join(base, "assets", "train_stops_kl.csv")


def normalize(name):
    s = name.strip().upper()
    s = re.sub(r"\([^)]*\)", "", s).strip()
    s = re.sub(r"^BANK RAKYAT\s+", "", s)
    s = re.sub(r"^CGC\s+", "", s)
    s = re.sub(
        r"\s*-\s*(REDONE|UOB|CBP COOPBANK PERTAMA|THE FACE STYLE|MAYBANK)\s*$", "", s
    ).strip()
    s = re.sub(r"\s*-\s*", " ", s)
    s = re.sub(r"([A-Z])(\d)", r"\1 \2", s)
    s = re.sub(r"(\d)([A-Z])", r"\1 \2", s)
    s = re.sub(r"\s+", " ", s)
    return s.strip()


with open(json_path, "r") as f:
    data = json.load(f)

csv_stations = {}
with open(csv_path, "r") as f:
    reader = csv.DictReader(f)
    for row in reader:
        name = normalize(row["station_name"])
        csv_stations[name] = {
            "lat": float(row["latitude"]),
            "lng": float(row["longitude"]),
            "id": row["station_id"].strip().upper(),
            "orig": row["station_name"],
        }

updates = 0
for s in data["stations"]:
    name = normalize(s["name"])
    if name in csv_stations:
        if csv_stations[name]["lat"] != 0 or csv_stations[name]["lng"] != 0:
            s["lat"] = csv_stations[name]["lat"]
            s["lng"] = csv_stations[name]["lng"]
            updates += 1
            print(
                f"  MATCH: {s['id']:12s} '{s['name']:35s}' < '{csv_stations[name]['orig']:30s}' -> ({s['lat']}, {s['lng']})"
            )

print(f"\nUpdated {updates} stations with real coordinates")

with open(json_path, "w") as f:
    json.dump(data, f, indent=2)

print("Done")
