import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "scripts"))

import aggregate_training_data as agg


class _FailingQuery:
    def select(self, *args, **kwargs):
        return self

    def gte(self, *args, **kwargs):
        return self

    def range(self, *args, **kwargs):
        return self

    def execute(self):
        raise RuntimeError("relation does not exist")


class _FailingClient:
    def table(self, name):
        return _FailingQuery()


class _FakeResponse:
    def __init__(self, data):
        self.data = data


class _StaticQuery:
    def __init__(self, data):
        self._data = data

    def select(self, *args, **kwargs):
        return self

    def gte(self, *args, **kwargs):
        return self

    def range(self, *args, **kwargs):
        return self

    def execute(self):
        return _FakeResponse(self._data)


class _StaticClient:
    def __init__(self, data):
        self._data = data

    def table(self, name):
        return _StaticQuery(self._data)


def test_missing_consent_views_return_empty_frames():
    client = _FailingClient()
    assert agg.pull_real_reports(client).empty
    assert agg.pull_trip_feedback(client).empty
    assert agg.pull_route_choice_feedback(client).empty


def test_real_reports_are_enriched_with_time_columns():
    rows = [
        {
            "stop_id": "KJ1",
            "occupancy_level": 3,
            "source_type": "user",
            "created_at": "2026-09-28T01:00:00+00:00",
            "user_id": "u1",
        }
    ]
    df = agg.pull_real_reports(_StaticClient(rows))
    assert len(df) == 1
    assert df.loc[0, "hour"] == 9
    assert df.loc[0, "is_weekend"] == 0
