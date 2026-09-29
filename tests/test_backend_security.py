from fastapi.testclient import TestClient

from backend import main as backend_main
from backend.main import app

RACE_START_BODY = {
    "party_id": "11111111-1111-1111-1111-111111111111",
    "category": "fastest",
    "target_mode": "shared_destination",
    "destination_stop_id": "KJ1",
}

TRIP_FEEDBACK_BODY = {
    "route_id": "KJ",
    "origin_stop": "KJ1",
    "dest_stop": "KJ15",
    "predicted_min": 20,
    "actual_min": 24,
}


def _raise_missing_credentials() -> None:
    raise RuntimeError("Supabase credentials not configured")


def _client() -> TestClient:
    return TestClient(app, raise_server_exceptions=False)


def test_race_start_requires_authentication(monkeypatch):
    monkeypatch.setattr(
        backend_main.crowd_service,
        "_get_supabase",
        _raise_missing_credentials,
    )
    response = _client().post("/race/start", json=RACE_START_BODY)
    assert response.status_code == 401


def test_race_start_ignores_x_user_id_header(monkeypatch):
    monkeypatch.setattr(
        backend_main.crowd_service,
        "_get_supabase",
        _raise_missing_credentials,
    )
    response = _client().post(
        "/race/start",
        json=RACE_START_BODY,
        headers={"x-user-id": "spoofed-user"},
    )
    assert response.status_code == 401


def test_account_delete_ignores_x_user_id_header(monkeypatch):
    monkeypatch.setattr(
        backend_main.crowd_service,
        "_get_supabase",
        _raise_missing_credentials,
    )
    response = _client().post(
        "/account/delete",
        headers={"x-user-id": "spoofed-user"},
    )
    assert response.status_code == 401


def test_invalid_bearer_token_is_rejected(monkeypatch):
    monkeypatch.setattr(
        backend_main.crowd_service,
        "_get_supabase",
        _raise_missing_credentials,
    )
    response = _client().post(
        "/race/start",
        json=RACE_START_BODY,
        headers={"Authorization": "Bearer not-a-real-token"},
    )
    assert response.status_code == 401
    assert response.json()["detail"] == "Invalid or expired token"


def test_crowd_report_allows_anonymous_requests(monkeypatch):
    monkeypatch.setattr(
        backend_main.crowd_service,
        "_get_supabase",
        _raise_missing_credentials,
    )
    response = _client().post(
        "/crowd/report",
        json={
            "stop_id": "ZZZZZ",
            "occupancy_level": 3,
            "latitude": 3.1,
            "longitude": 101.6,
        },
    )
    assert response.status_code == 400


def test_crowd_report_rejects_invalid_token(monkeypatch):
    monkeypatch.setattr(
        backend_main.crowd_service,
        "_get_supabase",
        _raise_missing_credentials,
    )
    response = _client().post(
        "/crowd/report",
        json={
            "stop_id": "KJ1",
            "occupancy_level": 3,
            "latitude": 3.1,
            "longitude": 101.6,
        },
        headers={"Authorization": "Bearer not-a-real-token"},
    )
    assert response.status_code == 401


def test_trip_feedback_hides_internal_errors(monkeypatch):
    monkeypatch.setattr(
        backend_main.crowd_service,
        "_get_supabase",
        _raise_missing_credentials,
    )
    response = _client().post("/trip/feedback", json=TRIP_FEEDBACK_BODY)
    assert response.status_code == 500
    detail = response.json()["detail"]
    assert detail == "Unable to record feedback right now."
    assert "Supabase" not in detail


def test_unhandled_errors_return_generic_message(monkeypatch):
    def _boom() -> dict:
        raise RuntimeError("secret internal detail")

    monkeypatch.setattr(backend_main.gtfs_service, "cache_metadata", _boom)
    response = _client().get("/health")
    assert response.status_code == 500
    assert response.json()["detail"] == "Internal server error"
    assert "secret internal detail" not in response.text
