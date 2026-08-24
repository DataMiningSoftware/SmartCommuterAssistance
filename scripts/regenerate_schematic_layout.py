import json
import re

TN = "app/assets/data/transit_network.json"
SL = "app/assets/schematic_layout.json"

CODE_TO_LINE = {
    "AG": "3",
    "SP": "4",
    "KJ": "5",
    "KG": "9",
    "MR": "8",
    "PY": "12",
    "BRT": "B1",
    "KT1": "1",
    "KT2": "2",
    "KS": "10",
    "ER6": "6",
    "ER7": "7",
}


def clean_name(raw):
    s = raw.strip()
    s = re.sub(r"\([^)]*\)", "", s).strip()
    s = re.sub(r"^BANK RAKYAT\s+", "", s, flags=re.I)
    s = re.sub(r"^CGC\s+", "", s, flags=re.I)
    s = re.sub(
        r"\s*-\s*(REDONE|UOB|CBP COOPBANK PERTAMA|THE FACE STYLE|MAYBANK)\s*$",
        "",
        s,
        flags=re.I,
    ).strip()
    s = re.sub(r"\s+", " ", s)
    return s


def main():
    tn = json.load(open(TN, encoding="utf-8"))
    sl = json.load(open(SL, encoding="utf-8"))

    unknown_codes = set()
    new_stations = {}
    for s in tn["stations"]:
        mapped = []
        for code in s["lines"]:
            lid = CODE_TO_LINE.get(code)
            if lid is None:
                unknown_codes.add(code)
                continue
            if lid not in mapped:
                mapped.append(lid)
        if not mapped:
            continue
        new_stations[s["id"]] = {
            "name": clean_name(s["name"]),
            "x": s["gridX"],
            "y": s["gridY"],
            "lines": mapped,
        }

    sl["stations"] = new_stations
    sl["gridColumns"] = 100
    sl["gridRows"] = 140
    sl["version"] = sl.get("version", 2)
    sl["sourceImage"] = None
    sl["extractionNote"] = (
        "Regenerated from transit_network.json; line assignments and "
        "coordinates are authoritative, no background image."
    )

    json.dump(sl, open(SL, "w", encoding="utf-8"), indent=2)
    print(f"Wrote {len(new_stations)} stations.")
    if unknown_codes:
        print(f"Unknown line codes (skipped): {sorted(unknown_codes)}")


if __name__ == "__main__":
    main()
