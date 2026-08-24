import json, os

base = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "app")
with open(os.path.join(base, "assets", "data", "transit_network.json"), "r") as f:
    data = json.load(f)

with open(os.path.join(base, "assets", "train_stops_kl.csv"), "r") as f:
    import csv

    reader = csv.DictReader(f)
    csv_names = set()
    for row in reader:
        csv_names.add(row["station_name"].strip().upper())

print("CSV names not found in JSON:")
for name in sorted(csv_names):
    found = False
    for s in data["stations"]:
        if s["name"].strip().upper() == name:
            found = True
            break
    if not found:
        print(f"  MISSING: {name}")

print("\nSearching for SS15 and KJ29:")
import re

for s in data["stations"]:
    name = s["name"].upper()
    if "SS15" in name or s["id"] == "KJ29":
        print(f"  {s['id']:12s} {s['name']:30s} lat={s['lat']} lng={s['lng']}")

print("\nStations with '-' in name (possible sponsor suffixes):")
for s in data["stations"]:
    if "-" in s["name"]:
        print(f"  {s['id']:12s} {s['name']:30s}")
