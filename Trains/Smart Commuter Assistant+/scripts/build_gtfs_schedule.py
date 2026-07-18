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
MALAYSIA_TZ = timezone(timedelta(hours=8), name="MYT")
OUTPUT_PATH = Path(__file__).resolve().parent.parent / "assets" / "data" / "gtfs_schedule.json"


def parse_gtfs_time(value: str) -> int:
    parts = value.strip().split(":")
    return int(parts[0]) * 3600 + int(parts[1]) * 60 + int(parts[2])


def parse_gtfs_date(value: str) -> date:
    return datetime.strptime(value.strip(), "%Y%m%d").date()


def download_gtfs() -> bytes:
    print(f"Downloading GTFS from {GTFS_URL}...")
    try:
        return urllib.request.urlopen(GTFS_URL, timeout=60).read()
    except ssl.SSLCertVerificationError:
        ctx = ssl._create_unverified_context()
        return urllib.request.urlopen(GTFS_URL, timeout=60, context=ctx).read()


def read_csv(archive: zipfile.ZipFile, name: str) -> list[dict[str, str]]:
    with archive.open(name) as f:
        return list(csv.DictReader(io.TextIOWrapper(f, encoding="utf-8-sig")))


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


def build_schedule() -> None:
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
    arrivals_count = sum(len(entry["s"]) for entry in result.values())
    file_size = OUTPUT_PATH.stat().st_size
    print(f"\nDone! {stops_count} stops, {arrivals_count} route/dest groups")
    print(f"Output: {OUTPUT_PATH} ({file_size / 1024:.1f} KB)")


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


if __name__ == "__main__":
    build_schedule()
