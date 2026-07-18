from __future__ import annotations

import csv
import io
import math
import ssl
import urllib.error
import urllib.request
import zipfile
from dataclasses import dataclass
from datetime import date, datetime, time, timedelta, timezone
from pathlib import Path
from typing import Iterable


GTFS_STATIC_URL = (
    "https://api.data.gov.my/gtfs-static/prasarana?category=rapid-rail-kl"
)
MALAYSIA_TZ = timezone(timedelta(hours=8), name="MYT")


@dataclass(frozen=True)
class GtfsStop:
    stop_id: str
    stop_name: str
    stop_lat: float
    stop_lon: float
    route_id: str


@dataclass(frozen=True)
class GtfsRoute:
    route_id: str
    short_name: str
    long_name: str
    color: str


@dataclass(frozen=True)
class GtfsTrip:
    route_id: str
    service_id: str
    trip_id: str
    headsign: str
    direction_id: str


@dataclass(frozen=True)
class GtfsStopTime:
    trip_id: str
    stop_id: str
    arrival_secs: int
    departure_secs: int
    stop_sequence: int


@dataclass(frozen=True)
class GtfsFrequency:
    trip_id: str
    start_secs: int
    end_secs: int
    headway_secs: int


@dataclass(frozen=True)
class GtfsCalendar:
    service_id: str
    active_weekdays: frozenset[int]
    start_date: date
    end_date: date

    def is_active(self, service_date: date) -> bool:
        return (
            self.start_date <= service_date <= self.end_date
            and service_date.weekday() in self.active_weekdays
        )


@dataclass(frozen=True)
class ScheduledArrival:
    stop_id: str
    stop_name: str
    route_id: str
    route_short_name: str
    route_long_name: str
    destination: str
    direction_id: str
    arrival_time: datetime
    minutes_until: int
    source: str = "gtfs_static_schedule"


class GtfsScheduleService:
    def __init__(self, cache_dir: Path | None = None) -> None:
        backend_dir = Path(__file__).resolve().parent
        self.cache_dir = cache_dir or backend_dir / "data" / "gtfs"
        self.cache_path = self.cache_dir / "rapid-rail-kl.zip"
        self.cache_ttl = timedelta(hours=24)
        self._feed: _GtfsFeed | None = None

    def feed_metadata(self) -> dict:
        feed = self._load_feed()
        return {
            "source": GTFS_STATIC_URL,
            "cache_path": str(self.cache_path),
            "cache_updated_at": datetime.fromtimestamp(
                self.cache_path.stat().st_mtime,
                tz=MALAYSIA_TZ,
            ).isoformat(),
            "stops": len(feed.stops),
            "routes": len(feed.routes),
            "trips": len(feed.trips),
        }

    def nearest_stops(
        self,
        *,
        latitude: float,
        longitude: float,
        limit: int = 5,
    ) -> list[tuple[GtfsStop, float]]:
        feed = self._load_feed()
        ranked = [
            (
                stop,
                _haversine_meters(
                    latitude,
                    longitude,
                    stop.stop_lat,
                    stop.stop_lon,
                ),
            )
            for stop in feed.stops.values()
        ]
        ranked.sort(key=lambda item: item[1])
        return ranked[: max(1, limit)]

    def arrivals_for_stop(
        self,
        stop_id: str,
        *,
        at: datetime | None = None,
        limit: int = 4,
    ) -> list[ScheduledArrival]:
        feed = self._load_feed()
        normalized_stop_id = stop_id.strip().upper()
        stop = feed.stops.get(normalized_stop_id)
        if stop is None:
            return []

        effective_time = _normalize_datetime(at or datetime.now(MALAYSIA_TZ))
        service_date = effective_time.date()
        query_secs = _seconds_since_midnight(effective_time)
        active_services = {
            service_id
            for service_id, calendar in feed.calendars.items()
            if calendar.is_active(service_date)
        }
        query_trip_ids = [
            trip.trip_id
            for trip in feed.trips.values()
            if trip.service_id in active_services
        ]

        arrivals: list[ScheduledArrival] = []
        for trip_id in query_trip_ids:
            trip = feed.trips[trip_id]
            stop_times = feed.stop_times_by_trip.get(trip_id, [])
            stop_time = next(
                (item for item in stop_times if item.stop_id == normalized_stop_id),
                None,
            )
            if stop_time is None:
                continue

            first_stop_time = stop_times[0]
            stop_offset = stop_time.arrival_secs - first_stop_time.arrival_secs
            frequencies = feed.frequencies_by_trip.get(trip_id, [])
            if frequencies:
                arrivals.extend(
                    self._arrivals_from_frequencies(
                        feed=feed,
                        stop=stop,
                        trip=trip,
                        stop_offset=stop_offset,
                        query_secs=query_secs,
                        service_date=service_date,
                        frequencies=frequencies,
                    )
                )
            elif stop_time.arrival_secs >= query_secs:
                arrivals.append(
                    _build_arrival(
                        feed=feed,
                        stop=stop,
                        trip=trip,
                        arrival_secs=stop_time.arrival_secs,
                        query_secs=query_secs,
                        service_date=service_date,
                    )
                )

        arrivals.sort(key=lambda item: item.arrival_time)
        return arrivals[: max(1, limit)]

    def _arrivals_from_frequencies(
        self,
        *,
        feed: "_GtfsFeed",
        stop: GtfsStop,
        trip: GtfsTrip,
        stop_offset: int,
        query_secs: int,
        service_date: date,
        frequencies: Iterable[GtfsFrequency],
    ) -> list[ScheduledArrival]:
        arrivals: list[ScheduledArrival] = []
        for frequency in frequencies:
            if frequency.headway_secs <= 0:
                continue
            first_possible_start = query_secs - stop_offset
            if first_possible_start <= frequency.start_secs:
                next_trip_start = frequency.start_secs
            else:
                intervals = math.ceil(
                    (first_possible_start - frequency.start_secs)
                    / frequency.headway_secs
                )
                next_trip_start = frequency.start_secs + (
                    intervals * frequency.headway_secs
                )
            if next_trip_start > frequency.end_secs:
                continue
            while next_trip_start <= frequency.end_secs and len(arrivals) < 20:
                arrivals.append(
                    _build_arrival(
                        feed=feed,
                        stop=stop,
                        trip=trip,
                        arrival_secs=next_trip_start + stop_offset,
                        query_secs=query_secs,
                        service_date=service_date,
                    )
                )
                next_trip_start += frequency.headway_secs
        return arrivals

    def _load_feed(self) -> "_GtfsFeed":
        self._ensure_cache()
        if self._feed is None:
            self._feed = _GtfsFeed.from_zip(self.cache_path)
        return self._feed

    def _ensure_cache(self) -> None:
        self.cache_dir.mkdir(parents=True, exist_ok=True)
        if self.cache_path.exists():
            age = datetime.now() - datetime.fromtimestamp(self.cache_path.stat().st_mtime)
            if age < self.cache_ttl:
                return

        tmp_path = self.cache_path.with_suffix(".zip.tmp")
        try:
            with urllib.request.urlopen(GTFS_STATIC_URL, timeout=30) as response:
                tmp_path.write_bytes(response.read())
        except (ssl.SSLCertVerificationError, urllib.error.URLError) as error:
            reason = getattr(error, "reason", error)
            if not isinstance(reason, ssl.SSLCertVerificationError):
                raise
            context = ssl._create_unverified_context()
            with urllib.request.urlopen(
                GTFS_STATIC_URL,
                timeout=30,
                context=context,
            ) as response:
                tmp_path.write_bytes(response.read())
        tmp_path.replace(self.cache_path)
        self._feed = None


@dataclass
class _GtfsFeed:
    stops: dict[str, GtfsStop]
    routes: dict[str, GtfsRoute]
    trips: dict[str, GtfsTrip]
    calendars: dict[str, GtfsCalendar]
    stop_times_by_trip: dict[str, list[GtfsStopTime]]
    frequencies_by_trip: dict[str, list[GtfsFrequency]]

    @classmethod
    def from_zip(cls, path: Path) -> "_GtfsFeed":
        with zipfile.ZipFile(path) as archive:
            stops = {
                stop.stop_id: stop
                for stop in _read_stops(_read_csv(archive, "stops.txt"))
            }
            routes = {
                route.route_id: route
                for route in _read_routes(_read_csv(archive, "routes.txt"))
            }
            trips = {
                trip.trip_id: trip
                for trip in _read_trips(_read_csv(archive, "trips.txt"))
            }
            calendars = {
                calendar.service_id: calendar
                for calendar in _read_calendar(_read_csv(archive, "calendar.txt"))
            }
            stop_times_by_trip: dict[str, list[GtfsStopTime]] = {}
            for stop_time in _read_stop_times(_read_csv(archive, "stop_times.txt")):
                stop_times_by_trip.setdefault(stop_time.trip_id, []).append(stop_time)
            for stop_times in stop_times_by_trip.values():
                stop_times.sort(key=lambda item: item.stop_sequence)

            frequencies_by_trip: dict[str, list[GtfsFrequency]] = {}
            for frequency in _read_frequencies(_read_csv(archive, "frequencies.txt")):
                frequencies_by_trip.setdefault(frequency.trip_id, []).append(frequency)

        return cls(
            stops=stops,
            routes=routes,
            trips=trips,
            calendars=calendars,
            stop_times_by_trip=stop_times_by_trip,
            frequencies_by_trip=frequencies_by_trip,
        )


def _read_csv(archive: zipfile.ZipFile, name: str) -> list[dict[str, str]]:
    with archive.open(name) as raw:
        text = io.TextIOWrapper(raw, encoding="utf-8-sig", newline="")
        return list(csv.DictReader(text))


def _read_stops(rows: Iterable[dict[str, str]]) -> Iterable[GtfsStop]:
    for row in rows:
        stop_id = row.get("stop_id", "").strip().upper()
        stop_name = row.get("stop_name", "").strip()
        if not stop_id or not stop_name:
            continue
        try:
            yield GtfsStop(
                stop_id=stop_id,
                stop_name=stop_name,
                stop_lat=float(row.get("stop_lat", "")),
                stop_lon=float(row.get("stop_lon", "")),
                route_id=row.get("route_id", "").strip().upper(),
            )
        except ValueError:
            continue


def _read_routes(rows: Iterable[dict[str, str]]) -> Iterable[GtfsRoute]:
    for row in rows:
        route_id = row.get("route_id", "").strip().upper()
        if not route_id:
            continue
        yield GtfsRoute(
            route_id=route_id,
            short_name=row.get("route_short_name", route_id).strip() or route_id,
            long_name=row.get("route_long_name", route_id).strip() or route_id,
            color=row.get("route_color", "").strip(),
        )


def _read_trips(rows: Iterable[dict[str, str]]) -> Iterable[GtfsTrip]:
    for row in rows:
        trip_id = row.get("trip_id", "").strip()
        if not trip_id:
            continue
        yield GtfsTrip(
            route_id=row.get("route_id", "").strip().upper(),
            service_id=row.get("service_id", "").strip(),
            trip_id=trip_id,
            headsign=row.get("trip_headsign", "").strip(),
            direction_id=row.get("direction_id", "").strip(),
        )


def _read_stop_times(rows: Iterable[dict[str, str]]) -> Iterable[GtfsStopTime]:
    for row in rows:
        trip_id = row.get("trip_id", "").strip()
        stop_id = row.get("stop_id", "").strip().upper()
        if not trip_id or not stop_id:
            continue
        try:
            yield GtfsStopTime(
                trip_id=trip_id,
                stop_id=stop_id,
                arrival_secs=_parse_gtfs_time(row.get("arrival_time", "")),
                departure_secs=_parse_gtfs_time(row.get("departure_time", "")),
                stop_sequence=int(row.get("stop_sequence", "0")),
            )
        except ValueError:
            continue


def _read_frequencies(rows: Iterable[dict[str, str]]) -> Iterable[GtfsFrequency]:
    for row in rows:
        trip_id = row.get("trip_id", "").strip()
        if not trip_id:
            continue
        try:
            yield GtfsFrequency(
                trip_id=trip_id,
                start_secs=_parse_gtfs_time(row.get("start_time", "")),
                end_secs=_parse_gtfs_time(row.get("end_time", "")),
                headway_secs=int(row.get("headway_secs", "0")),
            )
        except ValueError:
            continue


def _read_calendar(rows: Iterable[dict[str, str]]) -> Iterable[GtfsCalendar]:
    day_fields = [
        "monday",
        "tuesday",
        "wednesday",
        "thursday",
        "friday",
        "saturday",
        "sunday",
    ]
    for row in rows:
        service_id = row.get("service_id", "").strip()
        if not service_id:
            continue
        try:
            active_weekdays = frozenset(
                index
                for index, field in enumerate(day_fields)
                if row.get(field, "0").strip() == "1"
            )
            yield GtfsCalendar(
                service_id=service_id,
                active_weekdays=active_weekdays,
                start_date=_parse_gtfs_date(row.get("start_date", "")),
                end_date=_parse_gtfs_date(row.get("end_date", "")),
            )
        except ValueError:
            continue


def _build_arrival(
    *,
    feed: _GtfsFeed,
    stop: GtfsStop,
    trip: GtfsTrip,
    arrival_secs: int,
    query_secs: int,
    service_date: date,
) -> ScheduledArrival:
    route = feed.routes.get(trip.route_id)
    arrival_dt = datetime.combine(service_date, time.min, tzinfo=MALAYSIA_TZ) + timedelta(
        seconds=arrival_secs
    )
    return ScheduledArrival(
        stop_id=stop.stop_id,
        stop_name=stop.stop_name,
        route_id=trip.route_id,
        route_short_name=route.short_name if route else trip.route_id,
        route_long_name=route.long_name if route else trip.route_id,
        destination=_destination_from_headsign(trip.headsign),
        direction_id=trip.direction_id,
        arrival_time=arrival_dt,
        minutes_until=max(0, math.ceil((arrival_secs - query_secs) / 60)),
    )


def _destination_from_headsign(headsign: str) -> str:
    marker = " to "
    if marker in headsign:
        return headsign.split(marker, maxsplit=1)[1].strip()
    return headsign.strip()


def _normalize_datetime(value: datetime) -> datetime:
    if value.tzinfo is None:
        return value.replace(tzinfo=MALAYSIA_TZ)
    return value.astimezone(MALAYSIA_TZ)


def _seconds_since_midnight(value: datetime) -> int:
    local = _normalize_datetime(value)
    return (local.hour * 3600) + (local.minute * 60) + local.second


def _parse_gtfs_date(value: str) -> date:
    return datetime.strptime(value.strip(), "%Y%m%d").date()


def _parse_gtfs_time(value: str) -> int:
    parts = value.strip().split(":")
    if len(parts) != 3:
        raise ValueError(f"Invalid GTFS time: {value}")
    hours, minutes, seconds = (int(part) for part in parts)
    return (hours * 3600) + (minutes * 60) + seconds


def parse_query_datetime(value: str | None) -> datetime | None:
    if value is None or not value.strip():
        return None
    normalized = value.strip().replace("Z", "+00:00")
    parsed = datetime.fromisoformat(normalized)
    return _normalize_datetime(parsed)


def _haversine_meters(
    latitude: float,
    longitude: float,
    target_latitude: float,
    target_longitude: float,
) -> float:
    earth_radius_m = 6371000.0
    lat1 = math.radians(latitude)
    lat2 = math.radians(target_latitude)
    d_lat = math.radians(target_latitude - latitude)
    d_lon = math.radians(target_longitude - longitude)
    a = (
        math.sin(d_lat / 2) ** 2
        + math.cos(lat1) * math.cos(lat2) * math.sin(d_lon / 2) ** 2
    )
    c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a))
    return earth_radius_m * c
