# Smart Commuter Assistant+

[![Checklist](https://img.shields.io/badge/status-deployment%20checklist-blue)](../CHECKLIST.md)

Smart Commuter Assistant+ is a Flutter application for Klang Valley rail commuters. It combines station lookup, route planning, crowd forecasts, rider reports, local trip history, GTFS-based scheduled arrivals, and an interactive schematic transit map — all backed by Supabase and an optional FastAPI backend.

> **Pre-deployment checklist → [`CHECKLIST.md`](../CHECKLIST.md)** in the repo root.

**Author:** Muhammad Nawfal Bin Nadzrim

---

## Features

### Core
- Supabase email/password authentication with session restore
- Route planning across Klang Valley rail stops with interchange handling (local graph + optional FastAPI backend + fallback)
- Three route profiles: fastest, balanced, comfort
- Crowd forecast board with hourly occupancy levels (1–5)
- Rider-submitted crowd and delay reports with age-weighted blending
- Nearby station crowd forecast via GPS
- Scheduled arrivals from official Malaysia GTFS static feed (rapid-rail-kl)
- Interactive schematic transit map (Rapid Pulse-style) with tappable stations
- Geographic map view with OpenStreetMap tiles and route polylines
- Active trip tracking
- Favorite routes, recent searches, travel history, preferences
- Light/dark theme toggle

### Anti-Reset & Anti-Fraud Crowd System
- **Time-series storage:** Reports stored append-only, never overwritten
- **Time-decay blending:** SQL function blends ML forecast (40%) + age-weighted user reports (60%) + 14-day historical average
- **Daily snapshots:** `historical_crowds` table preserves blended levels per hour/weekday
- **Geo-fencing:** GPS must be within 500m of station (enforced server-side + client-side)
- **Rate limiting:** 1 report per station per 2 hours per user
- **Consensus:** Extreme reports (1 or 4–5) require corroboration within 30 minutes

### Offline & Resilience
- SQLite cache for transit stops, route connections, favorites, recent searches, travel history
- Automatic fallback: backend unavailable → local graph routing
- Network status banners (connected/disconnected)
- Connectivity-aware data refresh
- Sentry crash/error logging

---

## Tech Stack

| Layer | Technology |
|-------|-----------|
| Mobile | Flutter 3 / Dart 3, Material 3 Design |
| Backend | FastAPI + Uvicorn |
| Database | Supabase (Postgres) with Row Level Security |
| Local cache | SQLite via `sqflite` |
| Maps | `flutter_map` + OpenStreetMap tiles (geographic); percentage-based coordinate overlay (schematic) |
| GTFS | Malaysia Open API `rapid-rail-kl` static feed, 24h cache |
| ML | Python: scikit-learn RandomForest (default), LightGBM, XGBoost, Optuna |
| CI/CD | GitHub Actions (Flutter analyze/test, Python lint/test), Render.com deployment |
| Monitoring | Sentry |

---

## Quick Start

> Run these from the repository root.

### Prerequisites
- Flutter SDK (3.x)
- Android Studio / Android SDK (for Android) or Xcode (macOS, for iOS)
- Python 3.10+ (for backend/ML)
- A Supabase project with the schema applied

### 1. Install dependencies

```powershell
cd app
flutter pub get
```

### 2. Run the app

```powershell
cd app
Copy-Item env/dev.template.json env/dev.json
# Fill SUPABASE_URL, SUPABASE_ANON_KEY, BACKEND_URL, and optional SENTRY_DSN.
flutter run --dart-define-from-file=env/dev.json
```

`env/dev.json` is local-only and ignored by git. Do not put `SUPABASE_SERVICE_KEY` in any Flutter Dart-define file; the service-role key belongs only on the backend or worker.

### 3. (Optional) Start the FastAPI backend

```powershell
cd backend
.\run_backend.ps1
```

Or manually:

```powershell
cd backend
pip install -r requirements.txt
uvicorn main:app --reload --host 0.0.0.0 --port 8000
```

---

## Supabase Setup

### Required tables
- `train_stops_kl` — station catalog with lat/lon and route_id (import from CSV)
- `route_connections` — edges between stops
- `crowd_reports` — time-series log of user reports
- `crowd_forecast_hourly` — ML forecast baselines
- `historical_crowds` — daily blended snapshots (run migration)

### Required RPC functions
- `submit_crowd_report` — inserts reports with validation
- `get_blended_crowd_level` — returns time-decay blended occupancy
- `get_unique_stations` — station names + serving lines
- `snapshot_daily_blend` — cron: snapshots today's reports

### Run the migration (in order)

Open Supabase Dashboard → SQL Editor → paste and run each block in order:

**Step 0 — Import the station catalog**
1. Supabase Dashboard → Table Editor → **Import data via spreadsheet** → upload
   `scripts/train_stops_kl.csv` (167 rows) as table `train_stops_kl`.

**Step 1 — Base schema** (in `scripts/`)
2. `stop_catalog_setup.sql` — `normalize_stop_id()` + `transit_stops` (populated from `train_stops_kl`)
3. `route_connections_setup.sql` — edges table
4. `insert_connections.sql` — populates edges (regenerate with `python scripts/generate_routes.py` if the catalog changes)
5. `find_route_rpc_setup.sql` — `find_route` RPC
6. `crowd_reports_setup.sql` — reports table + `submit_crowd_report`
7. `crowd_forecast_setup.sql` — hourly forecast table

**Step 2 — Crowd system** (in `supabase/`)
8. `migration_crowd_system.sql` — geo/rate-limit columns, `historical_crowds`, `get_blended_crowd_level`, 7-param `submit_crowd_report`, `snapshot_daily_blend`
9. `migration_day_of_week.sql` — `day_of_week` column + day-aware blend
10. `migration_trip_feedback.sql` — `trip_feedback` table for ML retraining
11. `migration_get_unique_stations.sql` — `get_unique_stations` RPC
12. `rls_policies.sql` — Row Level Security
13. `migration_cleanup.sql` — drops the legacy 3-param RPC + dead `transit_stops`

### RLS note

When running queries in the Supabase SQL Editor, RLS does **not** apply — you run as superuser. RLS only applies to client requests made with the anon key from the Flutter app.

---

## Deploy Backend to Render

1. Go to [render.com](https://render.com) → New + → Web Service
2. Connect your GitHub repo
3. Settings:
   - **Name:** `smart-commuter-backend`
   - **Root Directory:** (repo root — leave blank or `.`)
   - **Runtime:** Python 3
   - **Build Command:** `pip install -r backend/requirements.txt`
   - **Start Command:** `cd backend && uvicorn main:app --host 0.0.0.0 --port $PORT`
   - **Health Check Path:** `/health`
4. Environment variables:
   - `SUPABASE_URL` = your Supabase project URL
   - `SUPABASE_SERVICE_KEY` = your Supabase service_role key
   - `CORS_ORIGINS` = allowed origins, comma-separated (`*` for development)
5. Build Flutter with the deployed backend URL:

```powershell
cd app
flutter build appbundle --release --dart-define-from-file=env/dev.json
```

For production, make sure `BACKEND_URL` in the Dart defines points to the deployed backend.

---

## Backend API Endpoints

| Method | Path | Description |
|--------|------|-------------|
| GET | `/health` | Health check + GTFS metadata |
| GET | `/plan-trip` | Route planning (Dijkstra, 3 profiles) |
| GET | `/arrivals/station/{stop_id}` | Scheduled arrivals from GTFS |
| GET | `/arrivals/nearest` | Nearest station + arrivals from GPS |
| POST | `/crowd/report` | Submit crowd report (geo-fenced, rate-limited, consensus) |
| GET | `/crowd/blend` | Get blended crowd level for a stop |
| GET | `/docs` | Swagger documentation |

---

## Repository Layout

```
.
├── .github/workflows/          # CI workflows
├── app/                        # Flutter app (Smart Commuter Assistant+)
│   ├── assets/
│   │   ├── data/               # transit_network.json, gtfs_schedule.json
│   │   └── images/             # klang_valley_map.jpeg, logo.png
│   ├── lib/
│   │   ├── constants/          # Colors, shadows, crowd levels
│   │   ├── main.dart           # Flutter entry point
│   │   ├── models/             # Data models
│   │   ├── screens/            # App screens
│   │   ├── services/           # Service files
│   │   └── widgets/            # Reusable widgets
│   ├── env/dev.json            # Local Dart defines (gitignored)
│   └── pubspec.yaml
├── backend/                    # FastAPI
│   ├── main.py                 # FastAPI app
│   ├── gtfs_service.py         # GTFS parser + arrival calculator
│   ├── crowd_service.py        # Crowd validation (geo-fence, rate-limit, consensus)
│   └── requirements.txt
├── scripts/                    # Python ML + SQL
│   ├── run_daily_pipeline.py   # Daily retrain orchestrator
│   ├── train_crowd_model.py    # Model training
│   ├── predict_and_upsert_crowd.py
│   └── *.sql                   # Base schema setup files
├── docker/                     # python-worker Dockerfile
├── tests/                      # Python tests
├── supabase/                   # Migrations + RLS policies
├── docker-compose.yml
├── requirements.txt
├── requirements-dev.txt
└── render.yaml                 # Render.com deployment config
```

---

## Tests

```powershell
cd app
flutter analyze
flutter test
```

```powershell
pytest -q
```
