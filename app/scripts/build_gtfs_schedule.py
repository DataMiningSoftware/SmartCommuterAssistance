import csv
import io
import json
import math
import ssl
import urllib.request
import zipfile
from collections import defaultdict
from datetime import date, datetime, time, timedelta, timezone
from pathlib import Path

GTFS_URL = "https://api.data.gov.my/gtfs-static/prasarana?category=rapid-rail-kl"
KTMB_URL = "https://api.data.gov.my/gtfs-static/ktmb"
KTMB_ROUTE_MAP = {
    "KC05_KB18": ("KT1", "KTM Seremban Line", "KTM Batu Caves - Pulau Sebang"),
    "KA15_KD19": ("KT2", "KTM Port Klang Line", "KTM Tanjung Malim - Pelabuhan Klang"),
}
KTMB_STOP_MAP_PATH = Path(__file__).resolve().parent.parent / "assets" / "data" / "ktmb_stop_map.json"
MALAYSIA_TZ = timezone(timedelta(hours=8), name="MYT")
OUTPUT_PATH = Path(__file__).resolve().parent.parent / "assets" / "data" / "gtfs_schedule.json"


def parse_gtfs_time(value: str) -> int:
    parts = value.strip().split(":")
    return int(parts[0]) * 3600 + int(parts[1]) * 60 + int(parts[2])


def parse_gtfs_date(value: str) -> date:
    return datetime.strptime(value.strip(), "%Y%m%d").date()


def download_gtfs(url: str = GTFS_URL) -> bytes:
    print(f"Downloading GTFS from {url}...")
    try:
        return urllib.request.urlopen(url, timeout=60).read()
    except ssl.SSLCertVerificationError:
        ctx = ssl._create_unverified_context()
        return urllib.request.urlopen(url, timeout=60, context=ctx).read()


def read_csv(archive: zipfile.ZipFile, name: str) -> list[dict[str, str]]:
    try:
        raw = archive.open(name)
    except KeyError:
        return []
    with raw:
        return list(csv.DictReader(io.TextIOWrapper(raw, encoding="utf-8-sig")))


def destination_from_headsign(headsign: str) -> str:
    marker = " to "
    if marker in headsign:
        return headsign.split(marker, maxsplit=1)[1].strip()
    return headsign.strip()


def route_id_to_app_id(route_id: str, short_name: str) -> str:
    rid = route_id.upper()
    if rid in ("KJL", "KJ"):
        return "KJ"
    if rid in ("KGL", "KAG", "KG"):
        return "KG"
    if rid in ("PYL", "PY"):
        return "PY"
    if rid in ("SPL", "SP"):
        return "SP"
    if rid in ("AGL", "AG"):
        return "AG"
    if rid in ("MRL", "MR"):
        return "MR"
    if rid.startswith("BRT"):
        return "BRT"
    if rid.startswith("KT") or rid in ("KT1", "KT2"):
        return rid
    if rid.startswith("ER") or rid in ("ER6", "ER7"):
        return rid
    if rid == "KS":
        return "KS"
    sn = short_name.upper().strip()
    if sn:
        return sn
    return rid


def build_schedule() -> tuple[dict, dict]:
    raw = download_gtfs()
    with zipfile.ZipFile(io.BytesIO(raw)) as archive:
        stops_raw = read_csv(archive, "stops.txt")
        routes_raw = read_csv(archive, "routes.txt")
        trips_raw = read_csv(archive, "trips.txt")
        stop_times_raw = read_csv(archive, "stop_times.txt")
        calendar_raw = read_csv(archive, "calendar.txt")
        frequencies_raw = read_csv(archive, "frequencies.txt")

    stops = {}
    for row in stops_raw:
        sid = row.get("stop_id", "").strip().upper()
        name = row.get("stop_name", "").strip()
        if sid and name:
            stops[sid] = name

    routes = {}
    for row in routes_raw:
        rid = row.get("route_id", "").strip().upper()
        sn = row.get("route_short_name", rid).strip() or rid
        ln = row.get("route_long_name", rid).strip() or rid
        if rid:
            routes[rid] = (sn, ln)

    trips = {}
    for row in trips_raw:
        tid = row.get("trip_id", "").strip()
        rid = row.get("route_id", "").strip().upper()
        sid = row.get("service_id", "").strip()
        headsign = row.get("trip_headsign", "").strip()
        if tid and rid:
            trips[tid] = (rid, sid, headsign)

    calendars = {}
    day_fields = ["monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday"]
    for row in calendar_raw:
        sid = row.get("service_id", "").strip()
        if not sid:
            continue
        days = frozenset(
            i for i, field in enumerate(day_fields) if row.get(field, "0").strip() == "1"
        )
        start = parse_gtfs_date(row.get("start_date", ""))
        end = parse_gtfs_date(row.get("end_date", ""))
        calendars[sid] = (days, start, end)

    frequencies = defaultdict(list)
    for row in frequencies_raw:
        tid = row.get("trip_id", "").strip()
        if not tid or tid not in trips:
            continue
        try:
            frequencies[tid].append({
                "start": parse_gtfs_time(row.get("start_time", "")),
                "end": parse_gtfs_time(row.get("end_time", "")),
                "headway": int(row.get("headway_secs", "0")),
            })
        except (ValueError, KeyError):
            pass

    stop_times_by_trip = defaultdict(list)
    for row in stop_times_raw:
        tid = row.get("trip_id", "").strip()
        sid = row.get("stop_id", "").strip().upper()
        if not tid or not sid or tid not in trips:
            continue
        try:
            stop_times_by_trip[tid].append({
                "stop_id": sid,
                "arrival": parse_gtfs_time(row.get("arrival_time", "")),
                "seq": int(row.get("stop_sequence", "0")),
            })
        except (ValueError, KeyError):
            pass

    for tid in stop_times_by_trip:
        stop_times_by_trip[tid].sort(key=lambda x: x["seq"])

    result = {}
    today = date.today()

    for tid, sts in stop_times_by_trip.items():
        trip = trips.get(tid)
        if not trip:
            continue
        rid, service_id, headsign = trip
        cal = calendars.get(service_id)
        if not cal:
            continue
        cal_days, cal_start, cal_end = cal
        if not (cal_start <= today <= cal_end):
            continue

        route = routes.get(rid, (rid, rid))
        app_rid = route_id_to_app_id(rid, route[0])
        dest = destination_from_headsign(headsign) or headsign
        first_stop = sts[0]

        freqs = frequencies.get(tid, [])
        if freqs:
            for st in sts:
                stop_offset = st["arrival"] - first_stop["arrival"]
                sid = st["stop_id"]
                if sid not in stops:
                    continue
                for freq in freqs:
                    secs = freq["start"]
                    while secs + stop_offset <= 86400 and secs <= freq["end"]:
                        arrival = secs + stop_offset
                        if arrival >= 0:
                            _add_arrival(result, sid, stops[sid], app_rid,
                                        route[0], route[1], dest, cal_days, arrival)
                        secs += freq["headway"]
                        if secs > freq["end"]:
                            break
        else:
            for st in sts:
                sid = st["stop_id"]
                if sid not in stops:
                    continue
                _add_arrival(result, sid, stops[sid], app_rid,
                            route[0], route[1], dest, cal_days, st["arrival"])

    days_label = {0: "0", 1: "1", 2: "2", 3: "3", 4: "4", 5: "5", 6: "6"}

    return result, days_label


def _add_arrival(
    result: dict, stop_id: str, stop_name: str,
    app_rid: str, short_name: str, long_name: str,
    dest: str, cal_days: frozenset, arrival_secs: int,
) -> None:
    if stop_id not in result:
        result[stop_id] = {"n": stop_name, "s": {}}
    key = f"{app_rid}|{dest}"
    if key not in result[stop_id]["s"]:
        result[stop_id]["s"][key] = {
            "r": app_rid, "rs": short_name, "rl": long_name, "d": dest,
            "dows": set(),
            "ts": [],
        }
    entry = result[stop_id]["s"][key]
    entry["dows"].update(cal_days)
    entry["ts"].append(arrival_secs)


def _compress_arrivals(groups: dict, days_label: dict) -> list:
    compressed = []
    for key, group in groups.items():
        if "by_dow" in group:
            entry = {
                "r": group["r"],
                "rs": group["rs"],
                "rl": group["rl"],
                "d": group["d"],
            }
            by_dow = {
                dow: sorted(set(times))
                for dow, times in group["by_dow"].items()
                if times
            }
            if len(by_dow) == 7 and len({tuple(v) for v in by_dow.values()}) == 1:
                entry["*"] = by_dow[0]
            else:
                for dow, times in by_dow.items():
                    entry[days_label[dow]] = times
            compressed.append(entry)
            continue
        if not group["ts"]:
            continue
        group["ts"].sort()
        group["ts"] = list(dict.fromkeys(group["ts"]))
        dows = sorted(group["dows"])
        entry = {
            "r": group["r"],
            "rs": group["rs"],
            "rl": group["rl"],
            "d": group["d"],
        }
        if len(dows) == 7:
            entry["*"] = group["ts"]
        else:
            for dow in dows:
                entry[days_label[dow]] = group["ts"]
        compressed.append(entry)
    return compressed


def _dart_days(cal_days: frozenset) -> frozenset:
    return frozenset((day + 1) % 7 for day in cal_days)


def build_ktmb(result: dict) -> None:
    stop_map = json.loads(KTMB_STOP_MAP_PATH.read_text(encoding="utf-8"))
    raw = download_gtfs(KTMB_URL)
    with zipfile.ZipFile(io.BytesIO(raw)) as archive:
        stops_raw = read_csv(archive, "stops.txt")
        trips_raw = read_csv(archive, "trips.txt")
        stop_times_raw = read_csv(archive, "stop_times.txt")
        calendar_raw = read_csv(archive, "calendar.txt")

    stops = {
        row["stop_id"].strip().upper(): row.get("stop_name", "").strip()
        for row in stops_raw
    }
    trips = {}
    for row in trips_raw:
        rid = row.get("route_id", "").strip().upper()
        if rid in KTMB_ROUTE_MAP:
            trips[row["trip_id"].strip()] = (rid, row.get("service_id", "").strip())

    calendars = {}
    day_fields = ["monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday"]
    for row in calendar_raw:
        sid = row.get("service_id", "").strip()
        if not sid:
            continue
        days = frozenset(
            i for i, field in enumerate(day_fields) if row.get(field, "0").strip() == "1"
        )
        calendars[sid] = (
            _dart_days(days),
            parse_gtfs_date(row.get("start_date", "")),
            parse_gtfs_date(row.get("end_date", "")),
        )

    stop_times_by_trip = defaultdict(list)
    for row in stop_times_raw:
        tid = row.get("trip_id", "").strip()
        if tid not in trips:
            continue
        sid = row.get("stop_id", "").strip().upper()
        mapped = stop_map.get(sid)
        if mapped is None:
            continue
        try:
            stop_times_by_trip[tid].append({
                "stop_id": sid,
                "mapped": mapped,
                "arrival": parse_gtfs_time(row.get("arrival_time", "")),
                "seq": int(row.get("stop_sequence", "0")),
            })
        except (ValueError, KeyError):
            pass

    today = date.today()
    for tid, rows in stop_times_by_trip.items():
        rows.sort(key=lambda x: x["seq"])
        rid, service_id = trips[tid]
        cal = calendars.get(service_id)
        if not cal or not rows:
            continue
        cal_days, cal_start, cal_end = cal
        if not (cal_start <= today <= cal_end):
            continue
        dest = stops.get(rows[-1]["stop_id"], "")
        app_rid, short_name, long_name = KTMB_ROUTE_MAP[rid]
        for st in rows:
            _add_arrival(
                result,
                st["mapped"],
                stops.get(st["stop_id"], st["mapped"]),
                app_rid,
                short_name,
                long_name,
                dest,
                cal_days,
                st["arrival"],
            )


ERL_ROUTE_INFO = {
    "ER6": ("KLIA Ekspres", "ERL KLIA Ekspres"),
    "ER7": ("KLIA Transit", "ERL KLIA Transit"),
}
ERL_TRANSIT_OFFSETS = {
    "KJ15": 0,
    "SP15": 7,
    "PY41": 19,
    "SALAK_TINGGI": 29,
    "KLIA": 36,
    "KLIA2": 39,
}
ERL_TRANSIT_REVERSE_OFFSETS = {
    "KLIA2": 0,
    "KLIA": 4,
    "SALAK_TINGGI": 11,
    "PY41": 20,
    "SP15": 31,
    "KJ15": 39,
}


def _erl_departures(line: str, reverse: bool, weekend: bool) -> list[int]:
    if line == "ER6":
        start = 4 * 3600 + 55 * 60 if reverse else 5 * 3600
        return list(range(start, 24 * 3600 + 1, 20 * 60))
    start = 5 * 3600 + 18 * 60 if reverse else 5 * 3600 + 3 * 60
    times: list[int] = []
    current = start
    while current <= 24 * 3600:
        times.append(current)
        hour = current // 3600
        peak = (not weekend) and (7 <= hour < 9 or 17 <= hour < 19)
        current += (15 if peak else 30) * 60
    return times


def build_erl(result: dict) -> None:
    specs = [
        ("ER6", "KLIA T2", False, ["KJ15", "KLIA", "KLIA2"], {"KJ15": 0, "KLIA": 28, "KLIA2": 31}),
        ("ER6", "KL Sentral", True, ["KLIA2", "KLIA", "KJ15"], {"KLIA2": 0, "KLIA": 3, "KJ15": 31}),
        ("ER7", "KLIA T2", False, list(ERL_TRANSIT_OFFSETS), ERL_TRANSIT_OFFSETS),
        ("ER7", "KL Sentral", True, list(ERL_TRANSIT_REVERSE_OFFSETS), ERL_TRANSIT_REVERSE_OFFSETS),
    ]
    station_names = {
        "KJ15": "KL SENTRAL",
        "SP15": "BANDAR TASIK SELATAN",
        "PY41": "PUTRAJAYA SENTRAL",
        "SALAK_TINGGI": "Salak Tinggi",
        "KLIA": "KLIA T1",
        "KLIA2": "KLIA T2",
    }
    for line, destination, reverse, order, offsets in specs:
        short_name, long_name = ERL_ROUTE_INFO[line]
        for weekend in (False, True):
            dows = {0, 6} if weekend else {1, 2, 3, 4, 5}
            departures = _erl_departures(line, reverse, weekend)
            for stop_id in order:
                offset = offsets[stop_id]
                times = [t + offset for t in departures if t + offset <= 24 * 3600]
                _add_dow_group(
                    result,
                    stop_id,
                    station_names[stop_id],
                    line,
                    short_name,
                    long_name,
                    destination,
                    {dow: times for dow in dows},
                )


def _add_dow_group(
    result: dict,
    stop_id: str,
    stop_name: str,
    rid: str,
    short_name: str,
    long_name: str,
    dest: str,
    times_by_dow: dict,
) -> None:
    if stop_id not in result:
        result[stop_id] = {"n": stop_name, "s": {}}
    key = f"{rid}|{dest}"
    group = result[stop_id]["s"].get(key)
    if group is None:
        group = {
            "r": rid,
            "rs": short_name,
            "rl": long_name,
            "d": dest,
            "by_dow": {},
        }
        result[stop_id]["s"][key] = group
    for dow, times in times_by_dow.items():
        group["by_dow"].setdefault(dow, []).extend(times)


def main() -> None:
    result, days_label = build_schedule()
    build_ktmb(result)
    build_erl(result)

    for sid in result:
        result[sid]["s"] = _compress_arrivals(result[sid]["s"], days_label)

    output = {
        "generated_at": datetime.now(MALAYSIA_TZ).isoformat(),
        "stops": result,
    }
    OUTPUT_PATH.parent.mkdir(parents=True, exist_ok=True)
    with open(OUTPUT_PATH, "w", encoding="utf-8") as f:
        json.dump(output, f, ensure_ascii=False, separators=(",", ":"))

    stops_count = len(result)
    groups_count = sum(len(entry["s"]) for entry in result.values())
    file_size = OUTPUT_PATH.stat().st_size
    print(f"\nDone! {stops_count} stops, {groups_count} route/dest groups")
    print(f"Output: {OUTPUT_PATH} ({file_size / 1024:.1f} KB)")


if __name__ == "__main__":
    main()
