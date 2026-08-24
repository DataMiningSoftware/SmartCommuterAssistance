import json, os

base = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "app")
with open(os.path.join(base, "assets", "schematic_layout.json"), "r") as f:
    data = json.load(f)

keep_lines = {"3", "4", "5", "8", "9", "12", "B1"}
calibrated = {}
for sid, s in data["stations"].items():
    matching = [l for l in s["lines"] if l in keep_lines]
    if matching:
        calibrated[sid] = {"name": s["name"], "lines": matching}

print(f"Calibrated stations: {len(calibrated)}\n")
for sid, s in sorted(calibrated.items()):
    lines_str = json.dumps(s["lines"])
    print(f'  "{sid}": {{"name": "{s["name"]}", "lines": {lines_str}}},')
