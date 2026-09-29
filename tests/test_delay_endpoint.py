from fastapi.testclient import TestClient

from backend.main import app


def _client() -> TestClient:
    return TestClient(app, raise_server_exceptions=False)


def test_delay_report_requires_line_id():
    response = _client().post(
        "/crowd/delay",
        json={"stop_id": "KJ1", "latitude": 3.1, "longitude": 101.6},
    )
    assert response.status_code == 422


def test_delay_report_requires_location():
    response = _client().post(
        "/crowd/delay",
        json={"stop_id": "KJ1", "line_id": "KJ"},
    )
    assert response.status_code == 400
    assert "Location" in response.json()["detail"]


def test_delay_report_accepts_direction_field():
    response = _client().post(
        "/crowd/delay",
        json={
            "stop_id": "KJ1",
            "line_id": "KJ",
            "direction": "Gombak",
        },
    )
    assert response.status_code == 400
    assert "Location" in response.json()["detail"]
