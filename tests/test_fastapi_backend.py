from pathlib import Path
from unittest.mock import patch

import pytest
from fastapi.testclient import TestClient

from backend.main import app, load_network


@pytest.fixture
def client():
    return TestClient(app)


def test_health_endpoint(client):
    response = client.get("/health")
    assert response.status_code == 200
    data = response.json()
    assert data["status"] == "ok"
    assert "stops" in data
    assert "edges" in data
    assert "gtfs" in data


def test_arrivals_station_not_found(client):
    response = client.get("/arrivals/station/ZZZZZ")
    assert response.status_code == 404
    assert "No scheduled arrivals" in response.json()["detail"]


def test_arrivals_nearest_missing_params(client):
    response = client.get("/arrivals/nearest")
    assert response.status_code == 422


def test_arrivals_nearest_invalid_coords(client):
    response = client.get("/arrivals/nearest?lat=999&lon=999")
    assert response.status_code == 422


def test_plan_trip_missing_params(client):
    response = client.get("/plan-trip")
    assert response.status_code == 422


def test_plan_trip_unknown_origin(client):
    response = client.get(
        "/plan-trip",
        params={
            "origin": "ZZZZZ",
            "destination": "KJ1",
            "departure": "2026-07-18T08:00:00Z",
        },
    )
    assert response.status_code == 404


def test_plan_trip_unknown_destination(client):
    response = client.get(
        "/plan-trip",
        params={
            "origin": "KJ15",
            "destination": "ZZZZZ",
            "departure": "2026-07-18T08:00:00Z",
        },
    )
    assert response.status_code == 404


def test_plan_trip_success(client):
    response = client.get(
        "/plan-trip",
        params={
            "origin": "KJ15",
            "destination": "KJ1",
            "departure": "2026-07-18T08:00:00Z",
        },
    )
    assert response.status_code == 200
    data = response.json()
    assert "routes" in data
    assert "generatedAt" in data
    assert len(data["routes"]) > 0
    route = data["routes"][0]
    assert "routeId" in route
    assert "origin" in route
    assert "destination" in route
    assert "totalDurationMinutes" in route


def test_network_load():
    network = load_network()
    assert "stops_by_id" in network
    assert "adjacency" in network
    assert len(network["stops_by_id"]) > 0
    assert len(network["adjacency"]) > 0
