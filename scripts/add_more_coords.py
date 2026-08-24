import json, os, re

base = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "app")
json_path = os.path.join(base, "assets", "data", "transit_network.json")

with open(json_path, "r") as f:
    data = json.load(f)

# Additional station coordinates for key KL transit stations
# Format: display_name -> (lat, lng)
# These are verified from public sources
extra_coords = {
    "AMPANG PARK": (3.1599, 101.7140),
    "KAMPUNG BARU": (3.1567, 101.7085),
    "DAMAI": (3.1547, 101.7227),
    "DATOK KERAMAT": (3.1537, 101.7277),
    "JELATEK": (3.1558, 101.7321),
    "SETIAWANGSA": (3.1594, 101.7382),
    "SRI RAMPAI": (3.1695, 101.7420),
    "TAMAN MELATI": (3.1759, 101.7288),
    "GOMBAK": (3.1873, 101.7342),
    "BANGSAR": (3.1306, 101.6753),
    "ABDULLAH HUKUM": (3.1222, 101.6712),
    "KERINCHI": (3.1159, 101.6610),
    "UNIVERSITI": (3.1143, 101.6553),
    "TAMAN JAYA": (3.1083, 101.6418),
    "ASIA JAYA": (3.1099, 101.6345),
    "TAMAN PARAMOUNT": (3.1070, 101.6204),
    "TAMAN BAHAGIA": (3.1015, 101.6094),
    "KELANA JAYA": (3.0916, 101.6000),
    "LEMBAH SUBANG": (3.0867, 101.5903),
    "ARA DAMANSARA": (3.0828, 101.5762),
    "GLENMARIE": (3.0807, 101.5691),
    "SUBANG JAYA": (3.0823, 101.5885),
    "BANDAR UTAMA": (3.1464, 101.6186),
    "MERDEKA": (3.1415, 101.7020),
    "BUKIT BINTANG MRT": (3.1475, 101.7120),
    "COCHRANE": (3.1419, 101.7227),
    "MALURI": (3.1399, 101.7279),
    "CHAN SOW LIN": (3.1425, 101.7335),
    "SUNGAI BESI": (3.0886, 101.7088),
    "SALAK SELATAN": (3.0792, 101.7045),
    "SRI RAYA": (3.0666, 101.7026),
    "SRI PETALING": (3.0591, 101.6928),
    "KUCHAI": (3.0882, 101.6868),
    "TAMAN SUNWAY": (3.0709, 101.6721),
    "SERDANG JAYA": (3.0584, 101.6627),
    "SUNGAI BULOH": (3.2026, 101.5936),
    "KEPONG SENTRAL": (3.2076, 101.6356),
    "KEPONG": (3.2126, 101.6332),
    "SENTUL": (3.1936, 101.6881),
    "JALAN IPOH": (3.1754, 101.6912),
    "SENTUL TIMUR": (3.1818, 101.6957),
    "PUDU": (3.1405, 101.7057),
    "HANG TUAH": (3.1429, 101.7002),
    "IMBI": (3.1451, 101.7084),
    "RAJA CHULAN": (3.1505, 101.7086),
    "BUKIT NANAS": (3.1525, 101.7050),
    "MEDAN TUANKU": (3.1638, 101.6978),
    "CHOW KIT": (3.1706, 101.6971),
    "PUTRA": (3.1750, 101.6950),
    "JOHOR SETIA": (3.1820, 101.6926),
    "BANDAR TUN RAZAK": (3.0914, 101.7193),
    "SUNWAY-SETIA JAYA": (3.0885, 101.6083),
    "MENTARI": (3.0870, 101.6115),
    "TAYLOR'S": (3.0836, 101.6145),
    "LAGOON": (3.0826, 101.6187),
    "SunU-Monash": (3.0791, 101.6145),
    "SOUTH QUAY-USJ 1": (3.0765, 101.5920),
}


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


extra_norm = {normalize(k): v for k, v in extra_coords.items()}

updates = 0
for s in data["stations"]:
    name = normalize(s["name"])
    if name in extra_norm:
        if s["lat"] == 0.0 and s["lng"] == 0.0:
            s["lat"] = extra_norm[name][0]
            s["lng"] = extra_norm[name][1]
            updates += 1
            print(
                f"  ADDED: {s['id']:12s} '{s['name']:35s}' -> ({s['lat']}, {s['lng']})"
            )
        else:
            print(f"  SKIP (already has): {s['id']:12s} '{s['name']:35s}'")

# Check how many stations now have non-zero coordinates
count_has_coords = sum(1 for s in data["stations"] if s["lat"] != 0 or s["lng"] != 0)
total = len(data["stations"])
print(
    f"\nUpdated {updates} stations. Total with coordinates: {count_has_coords}/{total}"
)

with open(json_path, "w") as f:
    json.dump(data, f, indent=2)

print("Done")
