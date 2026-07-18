# Smart Commuter Backend

FastAPI backend for Smart Commuter Assistant+ — provides route planning, GTFS scheduled arrivals, and crowd report validation.

## Quick Start (Windows / PowerShell)

```powershell
cd backend
.\run_backend.ps1
```

Or manually:

```powershell
pip install -r requirements.txt
uvicorn main:app --reload --host 0.0.0.0 --port 8000
```

Server: `http://127.0.0.1:8000`  
Swagger docs: `http://127.0.0.1:8000/docs`  
Health check: `http://127.0.0.1:8000/health`

## Environment Variables

| Variable | Required | Description |
|----------|----------|-------------|
| `SUPABASE_URL` | Yes | Supabase project URL |
| `SUPABASE_SERVICE_KEY` | Yes | Supabase service_role key (for crowd validation) |

## Endpoints

### `GET /health`
Returns backend status, stop count, edge count, and GTFS cache metadata.

### `GET /plan-trip`
Route planning with Dijkstra shortest-path on a graph built from `train_stops_kl.csv`.

**Params:** `origin`, `destination`, `departure` (ISO datetime), `maxRoutes` (1–6)

### `GET /arrivals/station/{stop_id}`
Returns next N scheduled train arrivals from the official Malaysia GTFS static feed (rapid-rail-kl). The feed is cached for 24 hours and refreshed automatically.

**Params:** `at` (ISO datetime, optional), `limit` (1–10, default 4)

### `GET /arrivals/nearest`
Returns the nearest station to given GPS coordinates plus its scheduled arrivals.

**Params:** `lat`, `lon`, `at` (optional), `limit` (optional)

### `POST /crowd/report`
Submit a crowd report with validation.

**Headers:** `x-user-id` (required — user UUID from Supabase Auth)

**Body:**
```json
{
  "stop_id": "KJ15",
  "occupancy_level": 4,
  "latitude": 3.1343,
  "longitude": 101.6861
}
```

**Validation:**
- Geo-fence: GPS must be within 500m of station
- Rate limit: 1 report per station per 2 hours per user
- Consensus: reports of 1 or 4–5 need corroboration within 30 min

### `GET /crowd/blend`
Returns the blended crowd level for a stop using the time-decay formula: 40% ML forecast + 60% age-weighted user reports (2h window), with fallback to 14-day historical average.

**Params:** `stop_id`, `hour` (0–23, optional), `is_weekend` (bool, optional)

## GTFS Data Source

The backend downloads the official Malaysia GTFS static feed from:
`https://api.data.gov.my/gtfs-static/prasarana?category=rapid-rail-kl`

It is cached at `backend/data/gtfs/rapid-rail-kl.zip` with a 24-hour TTL.

## Flutter Connection Notes

- Android emulator: `http://10.0.2.2:8000`
- iOS simulator / desktop: `http://127.0.0.1:8000`
- Physical device: use PC LAN IP, e.g. `http://192.168.1.5:8000`
- Production: `https://smart-commuter-backend.onrender.com`
