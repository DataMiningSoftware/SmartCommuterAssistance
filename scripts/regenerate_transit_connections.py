import json
import re
from collections import defaultdict
from pathlib import Path

TN = Path("app/assets/data/transit_network.json")

LINE_PREFIXES = {
    "AG": "AG",
    "SP": "SP",
    "KJ": "KJ",
    "KG": "KG",
    "PY": "PY",
    "MR": "MR",
    "BRT": "BRT",
    "KT1": "KT1",
    "KT2": "KT2",
    "KS": "KS",
    "ER6": "ER6",
    "ER7": "ER7",
    "JS": "JS",
}
PREFIX_TO_LINE = {v: k for k, v in LINE_PREFIXES.items()}


def _num(sid: str):
    m = re.match(r"^[A-Z]+(\d+)", sid)
    return int(m.group(1)) if m else None


def _belongs(sid: str, line: str, stations: dict) -> bool:
    prefix = re.match(r"^[A-Z]+", sid)
    if re.search(r"\d", sid):
        return PREFIX_TO_LINE.get(prefix.group(0)) == line
    return line in stations[sid]["lines"]


def _grid(sid: str, stations: dict):
    s = stations[sid]
    return (s.get("gridX", 0), s.get("gridY", 0))


def _insert_by_grid(nb: str, seq: list, stations: dict):
    gx, gy = _grid(nb, stations)

    def seg_dist(a, b):
        ax, ay = _grid(a, stations)
        bx, by = _grid(b, stations)
        dx, dy = bx - ax, by - ay
        if dx == 0 and dy == 0:
            return ((gx - ax) ** 2 + (gy - ay) ** 2) ** 0.5
        t = max(0.0, min(1.0, ((gx - ax) * dx + (gy - ay) * dy) / (dx * dx + dy * dy)))
        return ((gx - (ax + t * dx)) ** 2 + (gy - (ay + t * dy)) ** 2) ** 0.5

    best_i, best_d = 0, 1e18
    for i in range(len(seq) + 1):
        if i == 0:
            d = ((gx - _grid(seq[0], stations)[0]) ** 2 + (gy - _grid(seq[0], stations)[1]) ** 2) ** 0.5
        elif i == len(seq):
            d = ((gx - _grid(seq[-1], stations)[0]) ** 2 + (gy - _grid(seq[-1], stations)[1]) ** 2) ** 0.5
        else:
            d = seg_dist(seq[i - 1], seq[i])
        if d < best_d:
            best_d, best_i = d, i
    seq.insert(best_i, nb)


def _chain_by_grid(ids: list, stations: dict):
    if len(ids) < 2:
        return list(ids)
    remaining = set(ids)
    start = ids[0]
    remaining.remove(start)
    ordered = [start]
    cur = start
    while remaining:
        cur = min(
            remaining,
            key=lambda sid: (
                (_grid(sid, stations)[0] - _grid(cur, stations)[0]) ** 2
                + (_grid(sid, stations)[1] - _grid(cur, stations)[1]) ** 2
            )
            ** 0.5,
        )
        remaining.remove(cur)
        ordered.append(cur)
    return ordered


def _normalize_name(name: str) -> str:
    return re.sub(r"[^A-Z0-9]", "", name.upper())


def order_line(line: str, stations: dict) -> list:
    ids = [sid for sid in stations if _belongs(sid, line, stations)]
    numeric = sorted(
        [sid for sid in ids if _num(sid) is not None],
        key=lambda sid: (_num(sid), sid),
    )
    name_based = [sid for sid in ids if _num(sid) is None]
    if not numeric:
        return _chain_by_grid(name_based, stations)
    # Numeric stations form a reliable backbone. Name-based stations (which
    # have no trustworthy position) are appended after it so the backbone
    # stays physically adjacent.
    return list(numeric) + name_based


def regenerate(data: dict) -> list:
    stations = {s["id"]: s for s in data["stations"]}
    connections = []
    seen = set()

    for line in LINE_PREFIXES:
        ordered = order_line(line, stations)
        for a, b in zip(ordered, ordered[1:]):
            for f, t in ((a, b), (b, a)):
                key = (f, t, line, "standard_stop")
                if key not in seen:
                    seen.add(key)
                    connections.append(
                        {"from": f, "to": t, "minutes": 2, "type": "standard_stop", "route": line}
                    )

    by_name = defaultdict(list)
    for sid in stations:
        by_name[_normalize_name(stations[sid]["name"])].append(sid)

    for sids in by_name.values():
        if len(sids) < 2:
            continue
        for i in range(len(sids)):
            for j in range(i + 1, len(sids)):
                a, b = sids[i], sids[j]
                key = (a, b, "INTERCHANGE", "interchange")
                key2 = (b, a, "INTERCHANGE", "interchange")
                if key in seen or key2 in seen:
                    continue
                seen.add(key)
                seen.add(key2)
                connections.append(
                    {"from": a, "to": b, "minutes": 3, "type": "interchange", "route": "INTERCHANGE"}
                )
                connections.append(
                    {"from": b, "to": a, "minutes": 3, "type": "interchange", "route": "INTERCHANGE"}
                )
    return connections


def main():
    data = json.load(open(TN, encoding="utf-8"))
    backup = TN.with_suffix(".json.bak")
    backup.write_text(json.dumps(data, indent=2), encoding="utf-8")
    new_connections = regenerate(data)
    data["connections"] = new_connections
    TN.write_text(json.dumps(data, indent=2), encoding="utf-8")
    print(
        f"Regenerated {len(new_connections)} connections "
        f"(backup at {backup.name})."
    )


if __name__ == "__main__":
    main()
