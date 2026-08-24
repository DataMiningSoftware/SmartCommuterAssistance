"""Crowd report service with geo-fencing, rate limiting, and consensus."""

from __future__ import annotations

import json
import os
from datetime import datetime, timedelta, timezone
from math import atan2, cos, radians, sin, sqrt
from pathlib import Path
from typing import Dict, Optional, Tuple

from dotenv import load_dotenv
from httpx import Client as HttpxClient
from supabase import Client as SupabaseClient
from supabase import create_client as create_supabase_client

load_dotenv()

MALAYSIA_TZ = timezone(timedelta(hours=8), name="MYT")


def _load_config_from_dev_json() -> Dict[str, str]:
    """Fall back to the Flutter env/dev.json for backend-only settings.

    The repo's single source of truth for local config is ``env/dev.json``
    (JSON, used by ``--dart-define-from-file``). Environment variables always
    take precedence; this only fills in missing values so the backend can be
    run directly from the repo without duplicating config.
    """
    try:
        dev_json = (
            Path(__file__).resolve().parents[1] / "app" / "env" / "dev.json"
        )
        if not dev_json.exists():
            return {}
        with dev_json.open("r", encoding="utf-8") as fh:
            data = json.load(fh)
        if not isinstance(data, dict):
            return {}
        return {str(k): str(v) for k, v in data.items() if v is not None}
    except (OSError, ValueError):
        return {}


_dev_json_config = _load_config_from_dev_json()

SUPABASE_URL = os.getenv("SUPABASE_URL", _dev_json_config.get("SUPABASE_URL", ""))
SUPABASE_SERVICE_KEY = os.getenv(
    "SUPABASE_SERVICE_KEY", _dev_json_config.get("SUPABASE_SERVICE_KEY", "")
)

GEOFENCE_MAX_METERS = 500.0
RATE_LIMIT_HOURS = 2
CONSENSUS_WINDOW_MINUTES = 30


class CrowdReportResult:
    def __init__(
        self,
        accepted: bool,
        message: str,
        stop_id: str = "",
        occupancy_level: int = 0,
    ):
        self.accepted = accepted
        self.message = message
        self.stop_id = stop_id
        self.occupancy_level = occupancy_level


class CrowdService:
    """Handles crowd report validation and submission."""

    def __init__(self) -> None:
        self._supabase: Optional[SupabaseClient] = None
        self._http: Optional[HttpxClient] = None

    def _get_supabase(self) -> SupabaseClient:
        if self._supabase is None:
            if not SUPABASE_URL or not SUPABASE_SERVICE_KEY:
                raise RuntimeError("Supabase credentials not configured")
            self._supabase = create_supabase_client(SUPABASE_URL, SUPABASE_SERVICE_KEY)
        return self._supabase

    def _get_http(self) -> HttpxClient:
        if self._http is None:
            self._http = HttpxClient(timeout=10.0)
        return self._http

    @staticmethod
    def haversine_meters(lat1: float, lon1: float, lat2: float, lon2: float) -> float:
        EARTH_RADIUS = 6_371_000.0
        dlat = radians(lat2 - lat1)
        dlon = radians(lon2 - lon1)
        a = (
            sin(dlat / 2) ** 2
            + cos(radians(lat1)) * cos(radians(lat2)) * sin(dlon / 2) ** 2
        )
        return EARTH_RADIUS * 2 * atan2(sqrt(a), sqrt(1 - a))

    def check_geofence(
        self,
        report_lat: float,
        report_lon: float,
        stop_lat: float,
        stop_lon: float,
    ) -> Tuple[bool, float]:
        distance = self.haversine_meters(report_lat, report_lon, stop_lat, stop_lon)
        return distance <= GEOFENCE_MAX_METERS, round(distance, 1)

    def get_stop_coordinates(self, stop_id: str) -> Optional[Tuple[float, float]]:
        try:
            supabase = self._get_supabase()
            result = (
                supabase.table("train_stops_kl")
                .select("stop_lat, stop_lon")
                .eq("stop_id", stop_id.upper())
                .limit(1)
                .execute()
            )
            if result.data and len(result.data) > 0:
                row = result.data[0]
                return float(row["stop_lat"]), float(row["stop_lon"])
        except Exception:
            pass
        return None

    def check_rate_limit(
        self, user_id: str, stop_id: str
    ) -> Tuple[bool, Optional[int]]:
        """Returns (is_allowed, minutes_until_next)."""
        try:
            supabase = self._get_supabase()
            result = (
                supabase.table("crowd_reports")
                .select("created_at")
                .eq("user_id", user_id)
                .eq("stop_id", stop_id.upper())
                .eq("source_type", "user")
                .order("created_at", desc=True)
                .limit(1)
                .execute()
            )
            if result.data and len(result.data) > 0:
                last_time_str = result.data[0]["created_at"]
                last_time = datetime.fromisoformat(last_time_str.replace("Z", "+00:00"))
                now = datetime.now(timezone.utc)
                elapsed = now - last_time
                if elapsed < timedelta(hours=RATE_LIMIT_HOURS):
                    remaining_minutes = int(
                        (timedelta(hours=RATE_LIMIT_HOURS) - elapsed).total_seconds()
                        / 60
                    )
                    return False, remaining_minutes
            return True, None
        except Exception:
            return True, None

    def check_consensus(
        self, stop_id: str, occupancy_level: int, user_id: Optional[str] = None
    ) -> Tuple[bool, str]:
        """Check if extreme report needs corroboration."""
        if 2 <= occupancy_level <= 3:
            return True, ""

        try:
            supabase = self._get_supabase()
            cutoff = (
                datetime.now(timezone.utc) - timedelta(minutes=CONSENSUS_WINDOW_MINUTES)
            ).isoformat()

            query = (
                supabase.table("crowd_reports")
                .select("occupancy_level")
                .eq("stop_id", stop_id.upper())
                .eq("source_type", "user")
                .gte("created_at", cutoff)
            )
            if user_id:
                query = query.neq("user_id", user_id)
            result = query.order("created_at", desc=True).limit(5).execute()

            if not result.data:
                return True, "unverified"

            levels = [int(r["occupancy_level"]) for r in result.data]
            corroborating = [
                level for level in levels if abs(level - occupancy_level) <= 1
            ]
            if corroborating:
                return True, "corroborated"
            return False, "conflicting"
        except Exception:
            return True, "error_fallback"

    def submit_report(
        self,
        stop_id: str,
        occupancy_level: int,
        user_id: Optional[str] = None,
        latitude: Optional[float] = None,
        longitude: Optional[float] = None,
        session_id: Optional[str] = None,
    ) -> CrowdReportResult:
        stop_id = stop_id.strip().upper()

        # 1. Geo-fence check (location is required to verify proximity)
        if latitude is None or longitude is None:
            return CrowdReportResult(
                accepted=False,
                message="Location is required to verify you are within 500m of the station.",
            )
        coords = self.get_stop_coordinates(stop_id)
        if coords is None:
            return CrowdReportResult(
                accepted=False,
                message=f"Unknown station: {stop_id}",
            )
        within_fence, distance = self.check_geofence(
            latitude, longitude, coords[0], coords[1]
        )
        if not within_fence:
            return CrowdReportResult(
                accepted=False,
                message=f"You are {distance}m from {stop_id}. Please move within 500m of the station to report.",
            )

        # 2. Rate limit check
        if user_id:
            allowed, minutes_remaining = self.check_rate_limit(user_id, stop_id)
            if not allowed:
                return CrowdReportResult(
                    accepted=False,
                    message=f"Rate limited. Try again in {minutes_remaining} minutes.",
                )

        # 3. Consensus check
        consensus_ok, consensus_note = self.check_consensus(
            stop_id, occupancy_level, user_id or ""
        )
        if not consensus_ok:
            return CrowdReportResult(
                accepted=False,
                message=(
                    "This report conflicts with recent reports for this station. "
                    "Please re-check the crowd level."
                ),
            )

        try:
            supabase = self._get_supabase()
            data: Dict = {
                "stop_id": stop_id,
                "occupancy_level": max(1, min(5, occupancy_level)),
                "source_type": "user",
            }
            if user_id:
                data["user_id"] = user_id
            if latitude is not None:
                data["latitude"] = latitude
            if longitude is not None:
                data["longitude"] = longitude
            if session_id is not None:
                data["session_id"] = session_id

            supabase.table("crowd_reports").insert(data).execute()

            message = "Report submitted."
            if consensus_note == "unverified":
                message = "Report submitted (awaiting verification)."

            return CrowdReportResult(
                accepted=True,
                message=message,
                stop_id=stop_id,
                occupancy_level=occupancy_level,
            )
        except Exception as e:
            return CrowdReportResult(
                accepted=False,
                message=f"Failed to submit report: {e}",
            )
