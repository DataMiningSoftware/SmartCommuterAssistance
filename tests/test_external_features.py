import sys
from datetime import datetime
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "scripts"))

import fetch_external_features as fef
from crowd_feature_utils import (
    StopMetadata,
    build_feature_row,
    estimate_occupancy_percent,
)


def test_ratio_uses_same_weekday_baseline():
    history = [
        ("2026-09-01", 100),
        ("2026-09-02", 100),
        ("2026-09-03", 100),
        ("2026-09-04", 100),
        ("2026-09-08", 120),
        ("2026-09-09", 100),
        ("2026-09-10", 100),
        ("2026-09-11", 100),
        ("2026-09-15", 130),
    ]
    ratio = fef.compute_ridership_ratio(history, len(history) - 1)
    assert 1.18 <= ratio <= 1.19


def test_ratio_clamps_and_defaults():
    history = [("2026-09-01", 100), ("2026-09-08", 100), ("2026-09-15", 500)]
    assert fef.compute_ridership_ratio(history, 2) == 1.5
    assert fef.compute_ridership_ratio([("2026-09-15", 500)], 0) == 1.0


def test_holiday_calendar_loads_expected_dates():
    holidays = fef.load_holidays()
    assert "2026-08-31" in holidays
    assert "2026-12-25" in holidays
    assert "2026-12-11" in holidays
    assert "2026-02-17" in holidays


def test_feature_row_includes_external_features():
    stop = StopMetadata(
        stop_id="KJ1",
        stop_name="GOMBAK",
        route_id="KJ",
        is_interchange=False,
    )
    row = build_feature_row(
        stop,
        datetime(2026, 9, 30, 8, 0),
        is_raining=1,
        rain_mm=7.5,
        ridership_ratio=1.2,
    )
    assert row["rain_mm"] == 7.5
    assert row["ridership_ratio"] == 1.2
    assert row["is_raining"] == 1


def test_demand_ratio_scales_occupancy():
    stop = StopMetadata(
        stop_id="KJ1",
        stop_name="GOMBAK",
        route_id="KJ",
        is_interchange=False,
    )
    when = datetime(2026, 9, 30, 8, 0)
    base = estimate_occupancy_percent(
        stop,
        build_feature_row(stop, when, is_raining=0),
    )
    lifted = estimate_occupancy_percent(
        stop,
        build_feature_row(stop, when, is_raining=0, ridership_ratio=1.4),
    )
    assert lifted > base
