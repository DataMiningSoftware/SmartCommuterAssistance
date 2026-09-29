from __future__ import annotations

from math import atan2, cos, radians, sin, sqrt
from typing import Dict, Iterable

ERL_FARES: Dict[str, Dict[str, float]] = {
    "ER6": {
        "KJ15|KLIA": 55.0,
        "KJ15|KLIA2": 55.0,
        "KLIA|KLIA2": 2.0,
    },
    "ER7": {
        "KJ15|SP15": 6.5,
        "KJ15|PY41": 14.0,
        "KJ15|SALAK_TINGGI": 18.3,
        "KJ15|KLIA": 55.0,
        "KJ15|KLIA2": 55.0,
        "SP15|PY41": 8.0,
        "SP15|SALAK_TINGGI": 12.4,
        "SP15|KLIA": 38.4,
        "SP15|KLIA2": 38.4,
        "PY41|SALAK_TINGGI": 4.7,
        "PY41|KLIA": 9.4,
        "PY41|KLIA2": 9.4,
        "SALAK_TINGGI|KLIA": 4.9,
        "SALAK_TINGGI|KLIA2": 4.9,
        "KLIA|KLIA2": 2.0,
    },
}

ESTIMATE_BASE = 1.4
ESTIMATE_PER_KM = 0.13
ESTIMATE_PER_TRANSFER = 0.35
ESTIMATE_MIN = 1.4
ESTIMATE_MAX = 8.0


def _haversine_km(lat1: float, lon1: float, lat2: float, lon2: float) -> float:
    radius = 6371.0
    d_lat = radians(lat2 - lat1)
    d_lon = radians(lon2 - lon1)
    a = (
        sin(d_lat / 2) ** 2
        + cos(radians(lat1)) * cos(radians(lat2)) * sin(d_lon / 2) ** 2
    )
    return 2 * radius * atan2(sqrt(a), sqrt(1 - a))


def _erl_lookup(line: str, from_stop: str, to_stop: str) -> float | None:
    table = ERL_FARES.get(line)
    if table is None:
        return None
    direct = table.get(f"{from_stop}|{to_stop}")
    if direct is not None:
        return direct
    return table.get(f"{to_stop}|{from_stop}")


def _estimate(distance_km: float, transfer_count: int) -> float:
    fare = ESTIMATE_BASE + distance_km * ESTIMATE_PER_KM + transfer_count * ESTIMATE_PER_TRANSFER
    return round(min(max(fare, ESTIMATE_MIN), ESTIMATE_MAX), 2)


def compute_fare(edges: Iterable, stops_by_id: Dict) -> float:
    edge_list = list(edges)
    if not edge_list:
        return 0.0

    transfer_count = sum(1 for edge in edge_list if edge.is_transfer)
    erl_total = 0.0
    other_distance = 0.0
    index = 0
    while index < len(edge_list):
        edge = edge_list[index]
        if edge.is_transfer:
            index += 1
            continue
        end = index
        while (
            end + 1 < len(edge_list)
            and not edge_list[end + 1].is_transfer
            and edge_list[end + 1].route_id == edge.route_id
        ):
            end += 1
        group = edge_list[index : end + 1]
        distance = 0.0
        for item in group:
            source = stops_by_id.get(item.from_stop_id)
            target = stops_by_id.get(item.to_stop_id)
            if source is not None and target is not None:
                distance += _haversine_km(
                    source.latitude,
                    source.longitude,
                    target.latitude,
                    target.longitude,
                )
        fare = _erl_lookup(edge.route_id, group[0].from_stop_id, group[-1].to_stop_id)
        if fare is not None:
            erl_total += fare
        else:
            other_distance += distance
        index = end + 1

    if erl_total > 0:
        estimate = 0.0
        if other_distance > 0:
            estimate = _estimate(other_distance, transfer_count)
        return round(erl_total + estimate, 2)
    return _estimate(other_distance, transfer_count)
