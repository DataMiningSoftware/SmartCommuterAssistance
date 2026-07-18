from __future__ import annotations

import csv
from dataclasses import dataclass
from datetime import datetime
from functools import lru_cache
from math import atan2, cos, radians, sin, sqrt
from pathlib import Path
from typing import Dict, Iterable, List, Optional

from fastapi import FastAPI, HTTPException, Query, Header
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel

from crowd_service import CrowdService
from gtfs_service import GtfsScheduleService, parse_query_datetime


class RouteStepModel(BaseModel):
    type: str
    line: str
    station: str
    durationMinutes: int
    instruction: str


class RouteModel(BaseModel):
    routeId: str
    origin: str
    destination: str
    steps: List[RouteStepModel]
    totalDurationMinutes: int
    totalDistance: float
    crowdLevel: str
    fare: float
    isFavorite: bool = False


class PlanResponse(BaseModel):
    routes: List[RouteModel]
    generatedAt: str


class ArrivalModel(BaseModel):
    stopId: str
    stopName: str
    routeId: str
    routeShortName: str
    routeLongName: str
    destination: str
    directionId: str
    arrivalTime: str
    minutesUntil: int
    source: str


class StationArrivalResponse(BaseModel):
    stopId: str
    stopName: str
    generatedAt: str
    arrivals: List[ArrivalModel]


class NearestStationArrivalResponse(BaseModel):
    stopId: str
    stopName: str
    routeId: str
    distanceMeters: float
    generatedAt: str
    arrivals: List[ArrivalModel]


@dataclass(frozen=True)
class StopRecord:
    stop_id: str
    stop_name: str
    route_id: str
    latitude: float
    longitude: float
    sequence_order: int


@dataclass(frozen=True)
class GraphEdge:
    from_stop_id: str
    to_stop_id: str
    route_id: str
    connection_type: str
    travel_minutes: int

    @property
    def is_transfer(self) -> bool:
        return "transfer" in self.connection_type.lower()


@dataclass(frozen=True)
class RouteCandidate:
    destination_stop_id: str
    edges: List[GraphEdge]
    total_minutes: int
    weighted_minutes: int
    transfer_count: int


class _RouteProfile:
    def __init__(self, route_id: str, transfer_penalty: int, crowd_penalty: int):
        self.route_id = route_id
        self.transfer_penalty = transfer_penalty
        self.crowd_penalty = crowd_penalty


class CrowdReportRequest(BaseModel):
    stop_id: str
    occupancy_level: int = 3
    latitude: Optional[float] = None
    longitude: Optional[float] = None
    session_id: Optional[str] = None


class CrowdReportResponse(BaseModel):
    accepted: bool
    message: str
    stop_id: str = ""
    occupancy_level: int = 0


class CrowdBlendRequest(BaseModel):
    stop_id: str
    hour: Optional[int] = None
    is_weekend: Optional[bool] = None


class CrowdBlendResponse(BaseModel):
    stop_id: str
    forecast_hour: int
    is_weekend: bool
    occupancy_level: int
    source_type: str
    user_reports_count: int


app = FastAPI(title="Smart Commuter Backend", version="0.3.0")
gtfs_service = GtfsScheduleService()
crowd_service = CrowdService()

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


@app.get("/health")
def health() -> dict:
    network = load_network()
    gtfs = gtfs_service.feed_metadata()
    return {
        "status": "ok",
        "stops": len(network["stops_by_id"]),
        "edges": len(network["adjacency"]),
        "gtfs": gtfs,
    }


@app.post("/crowd/report", response_model=CrowdReportResponse)
def submit_crowd_report(
    body: CrowdReportRequest,
    x_user_id: str = Header(None),
) -> CrowdReportResponse:
    if not x_user_id:
        raise HTTPException(status_code=401, detail="x-user-id header required")
    result = crowd_service.submit_report(
        stop_id=body.stop_id,
        occupancy_level=body.occupancy_level,
        user_id=x_user_id,
        latitude=body.latitude,
        longitude=body.longitude,
        session_id=body.session_id,
    )
    if not result.accepted:
        raise HTTPException(status_code=400, detail=result.message)
    return CrowdReportResponse(
        accepted=True,
        message=result.message,
        stop_id=result.stop_id,
        occupancy_level=result.occupancy_level,
    )


@app.get("/crowd/blend", response_model=CrowdBlendResponse)
def crowd_blend(
    stop_id: str = Query(...),
    hour: Optional[int] = Query(None, ge=0, le=23),
    is_weekend: Optional[bool] = Query(None),
) -> CrowdBlendResponse:
    import math

    v_hour = hour if hour is not None else datetime.now().hour
    v_is_weekend = is_weekend if is_weekend is not None else datetime.now().weekday() >= 5

    try:
        result = crowd_service._get_supabase().rpc(
            "get_blended_crowd_level",
            params={
                "p_stop_id": stop_id.upper(),
                "p_hour": v_hour,
                "p_is_weekend": v_is_weekend,
            },
        ).execute()
        if result.data and len(result.data) > 0:
            row = result.data[0]
            return CrowdBlendResponse(
                stop_id=row["stop_id"],
                forecast_hour=row["forecast_hour"],
                is_weekend=row["is_weekend"],
                occupancy_level=row["occupancy_level"],
                source_type=row["source_type"],
                user_reports_count=row.get("user_reports_count", 0),
            )
    except Exception:
        pass

    return CrowdBlendResponse(
        stop_id=stop_id.upper(),
        forecast_hour=v_hour,
        is_weekend=v_is_weekend,
        occupancy_level=2,
        source_type="fallback",
        user_reports_count=0,
    )


@app.get("/arrivals/station/{stop_id}", response_model=StationArrivalResponse)
def station_arrivals(
    stop_id: str,
    at: str | None = Query(
        None,
        description="Optional ISO datetime. Defaults to current Malaysia time.",
    ),
    limit: int = Query(4, ge=1, le=10),
) -> StationArrivalResponse:
    query_time = parse_query_datetime(at)
    arrivals = gtfs_service.arrivals_for_stop(stop_id, at=query_time, limit=limit)
    if not arrivals:
        raise HTTPException(
            status_code=404,
            detail=f"No scheduled arrivals found for stop: {stop_id}",
        )
    first = arrivals[0]
    return StationArrivalResponse(
        stopId=first.stop_id,
        stopName=first.stop_name,
        generatedAt=datetime.utcnow().isoformat() + "Z",
        arrivals=[to_arrival_model(arrival) for arrival in arrivals],
    )


@app.get("/arrivals/nearest", response_model=NearestStationArrivalResponse)
def nearest_station_arrivals(
    lat: float = Query(..., ge=-90, le=90),
    lon: float = Query(..., ge=-180, le=180),
    at: str | None = Query(
        None,
        description="Optional ISO datetime. Defaults to current Malaysia time.",
    ),
    limit: int = Query(4, ge=1, le=10),
) -> NearestStationArrivalResponse:
    nearest = gtfs_service.nearest_stops(latitude=lat, longitude=lon, limit=1)
    if not nearest:
        raise HTTPException(status_code=404, detail="No station data available")

    stop, distance_meters = nearest[0]
    query_time = parse_query_datetime(at)
    arrivals = gtfs_service.arrivals_for_stop(
        stop.stop_id,
        at=query_time,
        limit=limit,
    )
    return NearestStationArrivalResponse(
        stopId=stop.stop_id,
        stopName=stop.stop_name,
        routeId=stop.route_id,
        distanceMeters=round(distance_meters, 1),
        generatedAt=datetime.utcnow().isoformat() + "Z",
        arrivals=[to_arrival_model(arrival) for arrival in arrivals],
    )


@app.get("/plan-trip", response_model=PlanResponse)
def plan_trip(
    origin: str = Query(..., min_length=2),
    destination: str = Query(..., min_length=2),
    departure: str = Query(...),
    maxRoutes: int = Query(4, ge=1, le=6),
) -> PlanResponse:
    datetime.fromisoformat(departure.replace("Z", "+00:00"))
    network = load_network()

    origin_ids = resolve_stop_ids(origin, network)
    destination_ids = resolve_stop_ids(destination, network)
    if not origin_ids:
        raise HTTPException(status_code=404, detail=f"Unknown origin: {origin}")
    if not destination_ids:
        raise HTTPException(
            status_code=404,
            detail=f"Unknown destination: {destination}",
        )

    profiles = [
        _RouteProfile("fastest", transfer_penalty=0, crowd_penalty=0),
        _RouteProfile("balanced", transfer_penalty=2, crowd_penalty=1),
        _RouteProfile("comfort", transfer_penalty=5, crowd_penalty=2),
    ]

    candidates: list[RouteModel] = []
    seen_signatures: set[tuple[str, ...]] = set()
    for profile in profiles:
        candidate = best_path_for_profile(
            origin_ids=origin_ids,
            destination_ids=destination_ids,
            adjacency=network["adjacency"],
            profile=profile,
        )
        if candidate is None:
            continue
        signature = tuple(edge.to_stop_id for edge in candidate.edges)
        if signature in seen_signatures:
            continue
        seen_signatures.add(signature)
        candidates.append(
            to_route_model(
                candidate=candidate,
                route_id=f"api_{profile.route_id}",
                stops_by_id=network["stops_by_id"],
            )
        )
        if len(candidates) >= maxRoutes:
            break

    return PlanResponse(
        routes=candidates,
        generatedAt=datetime.utcnow().isoformat() + "Z",
    )


@lru_cache(maxsize=1)
def load_network() -> dict:
    repo_root = Path(__file__).resolve().parents[1]
    csv_path = repo_root / "lib" / "PythonScript" / "train_stops_kl.csv"
    stops: list[StopRecord] = []
    with csv_path.open("r", encoding="utf-8-sig", newline="") as fh:
        reader = csv.DictReader(fh)
        for row in reader:
            stop_id = (row.get("stop_id") or "").strip().upper()
            stop_name = (row.get("stop_name") or "").strip()
            route_id = normalize_route_id((row.get("route_id") or "").strip().upper())
            if not stop_id or not stop_name or not route_id:
                continue
            try:
                latitude = float(row.get("stop_lat") or 0.0)
                longitude = float(row.get("stop_lon") or 0.0)
            except ValueError:
                continue
            try:
                sequence_order = int(float(row.get("sequence_order") or 0))
            except ValueError:
                sequence_order = 0
            stops.append(
                StopRecord(
                    stop_id=stop_id,
                    stop_name=stop_name,
                    route_id=route_id,
                    latitude=latitude,
                    longitude=longitude,
                    sequence_order=sequence_order,
                )
            )

    stops_by_id = {stop.stop_id: stop for stop in stops}
    adjacency: Dict[str, List[GraphEdge]] = {stop.stop_id: [] for stop in stops}

    by_route: Dict[str, List[StopRecord]] = {}
    for stop in stops:
        by_route.setdefault(stop.route_id, []).append(stop)
    for route_id, route_stops in by_route.items():
        ordered = sorted(
            route_stops,
            key=lambda stop: (stop.sequence_order, stop.stop_id),
        )
        for left, right in zip(ordered, ordered[1:]):
            minutes = travel_minutes_between(left, right, fallback=2)
            add_edge(
                adjacency,
                GraphEdge(
                    left.stop_id, right.stop_id, route_id, "standard_stop", minutes
                ),
            )
            add_edge(
                adjacency,
                GraphEdge(
                    right.stop_id, left.stop_id, route_id, "standard_stop", minutes
                ),
            )

    by_station_name: Dict[str, List[StopRecord]] = {}
    for stop in stops:
        by_station_name.setdefault(stop.stop_name.upper(), []).append(stop)
    for station_stops in by_station_name.values():
        if len(station_stops) < 2:
            continue
        for index, left in enumerate(station_stops[:-1]):
            for right in station_stops[index + 1 :]:
                if left.route_id == right.route_id:
                    continue
                add_edge(
                    adjacency,
                    GraphEdge(
                        left.stop_id,
                        right.stop_id,
                        right.route_id,
                        "interchange_transfer",
                        3,
                    ),
                )
                add_edge(
                    adjacency,
                    GraphEdge(
                        right.stop_id,
                        left.stop_id,
                        left.route_id,
                        "interchange_transfer",
                        3,
                    ),
                )

    return {
        "stops_by_id": stops_by_id,
        "adjacency": adjacency,
    }


def to_arrival_model(arrival) -> ArrivalModel:
    return ArrivalModel(
        stopId=arrival.stop_id,
        stopName=arrival.stop_name,
        routeId=arrival.route_id,
        routeShortName=arrival.route_short_name,
        routeLongName=arrival.route_long_name,
        destination=arrival.destination,
        directionId=arrival.direction_id,
        arrivalTime=arrival.arrival_time.isoformat(),
        minutesUntil=arrival.minutes_until,
        source=arrival.source,
    )


def normalize_route_id(route_id: str) -> str:
    if route_id.startswith("KG") or route_id == "MRT":
        return "MRT"
    if route_id.startswith("PY"):
        return "PYL"
    if route_id.startswith("SP") or route_id.startswith("PH"):
        return "PH"
    return route_id[:3] if route_id else "N/A"


def add_edge(adjacency: Dict[str, List[GraphEdge]], edge: GraphEdge) -> None:
    edges = adjacency.setdefault(edge.from_stop_id, [])
    signature = (
        edge.to_stop_id,
        edge.route_id,
        edge.connection_type,
        edge.travel_minutes,
    )
    if any(
        (
            existing.to_stop_id,
            existing.route_id,
            existing.connection_type,
            existing.travel_minutes,
        )
        == signature
        for existing in edges
    ):
        return
    edges.append(edge)


def resolve_stop_ids(query: str, network: dict) -> list[str]:
    normalized = query.strip().upper()
    stops_by_id: Dict[str, StopRecord] = network["stops_by_id"]
    if normalized in stops_by_id:
        return [normalized]

    matches = [
        stop_id
        for stop_id, stop in stops_by_id.items()
        if stop.stop_name.upper() == normalized
    ]
    if matches:
        return sorted(matches)

    partial_matches = [
        stop_id
        for stop_id, stop in stops_by_id.items()
        if normalized in stop.stop_name.upper()
    ]
    return sorted(partial_matches)


def best_path_for_profile(
    origin_ids: Iterable[str],
    destination_ids: Iterable[str],
    adjacency: Dict[str, List[GraphEdge]],
    profile: _RouteProfile,
) -> RouteCandidate | None:
    best: RouteCandidate | None = None
    for origin_id in origin_ids:
        for destination_id in destination_ids:
            candidate = shortest_path(
                origin_stop_id=origin_id,
                destination_stop_id=destination_id,
                adjacency=adjacency,
                profile=profile,
            )
            if candidate is None:
                continue
            if best is None or candidate.weighted_minutes < best.weighted_minutes:
                best = candidate
    return best


def shortest_path(
    origin_stop_id: str,
    destination_stop_id: str,
    adjacency: Dict[str, List[GraphEdge]],
    profile: _RouteProfile,
) -> RouteCandidate | None:
    nodes = set(adjacency.keys())
    if origin_stop_id not in nodes or destination_stop_id not in nodes:
        return None

    distances: Dict[str, int] = {origin_stop_id: 0}
    previous_node: Dict[str, str] = {}
    previous_edge: Dict[str, GraphEdge] = {}
    visited: set[str] = set()

    while len(visited) < len(nodes):
        current_node = None
        current_distance = 10**9
        for node in nodes:
            if node in visited:
                continue
            node_distance = distances.get(node)
            if node_distance is None:
                continue
            if node_distance < current_distance:
                current_distance = node_distance
                current_node = node

        if current_node is None:
            break
        if current_node == destination_stop_id:
            break

        visited.add(current_node)
        for edge in adjacency.get(current_node, []):
            if edge.to_stop_id in visited:
                continue
            crowd_penalty = profile.crowd_penalty if not edge.is_transfer else 0
            transfer_penalty = profile.transfer_penalty if edge.is_transfer else 0
            candidate_distance = (
                current_distance
                + edge.travel_minutes
                + crowd_penalty
                + transfer_penalty
            )
            if candidate_distance < distances.get(edge.to_stop_id, 10**9):
                distances[edge.to_stop_id] = candidate_distance
                previous_node[edge.to_stop_id] = current_node
                previous_edge[edge.to_stop_id] = edge

    if (
        destination_stop_id not in previous_edge
        and origin_stop_id != destination_stop_id
    ):
        return None

    path: list[GraphEdge] = []
    cursor = destination_stop_id
    while cursor != origin_stop_id:
        edge = previous_edge.get(cursor)
        parent = previous_node.get(cursor)
        if edge is None or parent is None:
            return None
        path.append(edge)
        cursor = parent
    path.reverse()

    total_minutes = sum(edge.travel_minutes for edge in path)
    transfer_count = sum(1 for edge in path if edge.is_transfer)
    return RouteCandidate(
        destination_stop_id=destination_stop_id,
        edges=path,
        total_minutes=total_minutes,
        weighted_minutes=distances.get(destination_stop_id, total_minutes),
        transfer_count=transfer_count,
    )


def to_route_model(
    candidate: RouteCandidate,
    route_id: str,
    stops_by_id: Dict[str, StopRecord],
) -> RouteModel:
    if not candidate.edges:
        stop = stops_by_id[candidate.destination_stop_id]
        return RouteModel(
            routeId=route_id,
            origin=stop.stop_name,
            destination=stop.stop_name,
            steps=[],
            totalDurationMinutes=0,
            totalDistance=0.0,
            crowdLevel="Low",
            fare=0.0,
        )

    origin_stop = stops_by_id[candidate.edges[0].from_stop_id]
    destination_stop = stops_by_id[candidate.destination_stop_id]
    steps: list[RouteStepModel] = []
    total_distance = 0.0
    for edge in candidate.edges:
        from_stop = stops_by_id[edge.from_stop_id]
        to_stop = stops_by_id[edge.to_stop_id]
        total_distance += haversine_km(
            from_stop.latitude,
            from_stop.longitude,
            to_stop.latitude,
            to_stop.longitude,
        )
        if edge.is_transfer:
            instruction = f"Transfer at {to_stop.stop_name}"
            step_type = "transfer"
            line = "Interchange"
        else:
            instruction = f"Take {edge.route_id} to {to_stop.stop_name}"
            step_type = "train"
            line = edge.route_id
        steps.append(
            RouteStepModel(
                type=step_type,
                line=line,
                station=to_stop.stop_name,
                durationMinutes=edge.travel_minutes,
                instruction=instruction,
            )
        )

    crowd_level = (
        "High"
        if candidate.transfer_count >= 2 or candidate.total_minutes >= 40
        else "Medium" if candidate.total_minutes >= 25 else "Low"
    )
    fare = min(
        max(1.4 + (total_distance * 0.13) + (candidate.transfer_count * 0.35), 1.4), 8.0
    )

    return RouteModel(
        routeId=route_id,
        origin=origin_stop.stop_name,
        destination=destination_stop.stop_name,
        steps=steps,
        totalDurationMinutes=candidate.total_minutes,
        totalDistance=round(total_distance, 2),
        crowdLevel=crowd_level,
        fare=round(fare, 2),
    )


def travel_minutes_between(left: StopRecord, right: StopRecord, fallback: int) -> int:
    distance_km = haversine_km(
        left.latitude, left.longitude, right.latitude, right.longitude
    )
    if distance_km <= 0:
        return fallback
    estimated = max(2, round((distance_km / 0.55)))
    return min(estimated, 8)


def haversine_km(lat1: float, lon1: float, lat2: float, lon2: float) -> float:
    earth_radius_km = 6371.0
    d_lat = radians(lat2 - lat1)
    d_lon = radians(lon2 - lon1)
    lat1_r = radians(lat1)
    lat2_r = radians(lat2)
    a = sin(d_lat / 2) ** 2 + cos(lat1_r) * cos(lat2_r) * sin(d_lon / 2) ** 2
    c = 2 * atan2(sqrt(a), sqrt(1 - a))
    return earth_radius_km * c
