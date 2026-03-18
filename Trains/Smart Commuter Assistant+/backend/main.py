from datetime import datetime
from typing import List

from fastapi import FastAPI, Query
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel


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


app = FastAPI(title="Smart Commuter Backend", version="0.1.0")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


@app.get("/health")
def health() -> dict:
    return {"status": "ok"}


@app.get("/plan-trip", response_model=PlanResponse)
def plan_trip(
    origin: str = Query(..., min_length=2),
    destination: str = Query(..., min_length=2),
    departure: str = Query(...),
    maxRoutes: int = Query(4, ge=1, le=6),
) -> PlanResponse:
    # Parse for validation only. You can use this later in time-aware routing.
    datetime.fromisoformat(departure.replace("Z", "+00:00"))

    # Demo candidates. Replace with GTFS/real routing service later.
    routes = [
        RouteModel(
            routeId="api_r1",
            origin=origin,
            destination=destination,
            steps=[
                RouteStepModel(
                    type="train",
                    line="MRT Kajang",
                    station="Pasar Seni",
                    durationMinutes=5,
                    instruction="Take MRT Kajang to Pasar Seni",
                ),
                RouteStepModel(
                    type="train",
                    line="MRT Kajang",
                    station=destination,
                    durationMinutes=17,
                    instruction=f"Continue to {destination}",
                ),
            ],
            totalDurationMinutes=30,
            totalDistance=14.8,
            crowdLevel="Medium",
            fare=3.40,
        ),
        RouteModel(
            routeId="api_r2",
            origin=origin,
            destination=destination,
            steps=[
                RouteStepModel(
                    type="train",
                    line="LRT Kelana Jaya",
                    station="Masjid Jamek",
                    durationMinutes=7,
                    instruction="Take LRT Kelana Jaya to Masjid Jamek",
                ),
                RouteStepModel(
                    type="transfer",
                    line="Interchange",
                    station="Pasar Seni",
                    durationMinutes=3,
                    instruction="Walk transfer to Pasar Seni",
                ),
                RouteStepModel(
                    type="train",
                    line="MRT Kajang",
                    station=destination,
                    durationMinutes=16,
                    instruction=f"Take MRT Kajang to {destination}",
                ),
            ],
            totalDurationMinutes=33,
            totalDistance=15.2,
            crowdLevel="Low",
            fare=3.60,
        ),
        RouteModel(
            routeId="api_r3",
            origin=origin,
            destination=destination,
            steps=[
                RouteStepModel(
                    type="train",
                    line="KTM Seremban",
                    station="KL Sentral",
                    durationMinutes=8,
                    instruction="Take KTM Seremban to KL Sentral",
                ),
                RouteStepModel(
                    type="transfer",
                    line="Interchange",
                    station="Merdeka",
                    durationMinutes=4,
                    instruction="Transfer at Merdeka",
                ),
                RouteStepModel(
                    type="train",
                    line="MRT Kajang",
                    station=destination,
                    durationMinutes=15,
                    instruction=f"Take MRT Kajang to {destination}",
                ),
            ],
            totalDurationMinutes=35,
            totalDistance=16.1,
            crowdLevel="High",
            fare=3.80,
        ),
    ]

    is_kl_batu_pair = {origin.lower(), destination.lower()} == {"kl sentral", "batu caves"}
    if is_kl_batu_pair:
        routes.insert(
            0,
            RouteModel(
                routeId="api_direct_kls_btc",
                origin=origin,
                destination=destination,
                steps=[
                    RouteStepModel(
                        type="train",
                        line="KTM Seremban",
                        station=destination,
                        durationMinutes=14,
                        instruction=f"Take KTM Seremban direct to {destination}",
                    ),
                ],
                totalDurationMinutes=14,
                totalDistance=12.7,
                crowdLevel="Low",
                fare=2.90,
            ),
        )

    return PlanResponse(
        routes=routes[:maxRoutes],
        generatedAt=datetime.utcnow().isoformat() + "Z",
    )
