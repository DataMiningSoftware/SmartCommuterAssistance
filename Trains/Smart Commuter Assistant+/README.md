# Smart Commuter Assistant+

Smart Commuter Assistant+ is a Flutter application for Klang Valley rail commuters. It combines station lookup, route planning, crowd forecasts, rider reports, local trip history, GTFS-based scheduled arrivals, and an interactive schematic transit map — all backed by Supabase and an optional FastAPI backend.

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

### Prerequisites
- Flutter SDK (3.x)
- Android Studio / Android SDK (for Android) or Xcode (macOS, for iOS)
- Python 3.10+ (for backend/ML)
- A Supabase project with the schema applied

### 1. Install dependencies

```powershell
cd "Trains/Smart Commuter Assistant+"
flutter pub get
```

### 2. Run the app

```powershell
flutter run --dart-define-from-file=env/dev.json
```

The included `env/dev.json` contains Supabase credentials for the development project.

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
- `train_stops_kl` — station catalog with lat/lon and route_id
- `route_connections` — edges between stops
- `crowd_reports` — time-series log of user reports
- `crowd_forecast_hourly` — ML forecast baselines
- `historical_crowds` — daily blended snapshots (run migration)

### Required RPC functions
- `submit_crowd_report` — inserts reports with validation
- `get_blended_crowd_level` — returns time-decay blended occupancy
- `snapshot_daily_blend` — cron: snapshots today's reports

### Run the migration

Open Supabase Dashboard → SQL Editor → paste and run files in order:

1. `supabase/migration_crowd_system.sql` — creates tables, functions, indexes
2. `supabase/rls_policies.sql` — applies Row Level Security

### RLS note

When running queries in the Supabase SQL Editor, RLS does **not** apply — you run as superuser. RLS only applies to client requests made with the anon key from the Flutter app.

---

## Deploy Backend to Render

1. Go to [render.com](https://render.com) → New + → Web Service
2. Connect your GitHub repo
3. Settings:
   - **Name:** `smart-commuter-backend`
   - **Runtime:** Python 3
   - **Build Command:** `pip install -r "Trains/Smart Commuter Assistant+/backend/requirements.txt"`
   - **Start Command:** `uvicorn main:app --host 0.0.0.0 --port $PORT`
   - **Health Check Path:** `/health`
4. Environment variables:
   - `SUPABASE_URL` = your Supabase project URL
   - `SUPABASE_SERVICE_KEY` = your Supabase service_role key
5. Update `lib/services/backend_config_service.dart` with the Render URL

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
├── assets/
│   ├── data/map_stations.json  # Station coordinates for schematic map
│   └── images/                 # klang_valley_map.png, logo.png
├── backend/
│   ├── main.py                 # FastAPI app
│   ├── gtfs_service.py         # GTFS parser + arrival calculator
│   ├── crowd_service.py        # Crowd validation (geo-fence, rate-limit, consensus)
│   └── requirements.txt
├── lib/
│   ├── constants/              # Colors, shadows, crowd levels
│   ├── main.dart               # Flutter entry point
│   ├── models/                 # Data models
│   ├── screens/                # 11 app screens
│   ├── services/               # 16 service files
│   └── widgets/                # 9 reusable widgets
├── supabase/
│   ├── rls_policies.sql        # Row Level Security policies
│   └── migration_crowd_system.sql  # Time-decay crowd system
├── env/dev.json                # Local Dart defines
├── pubspec.yaml
└── render.yaml                 # Render.com deployment config
```

---

## Tests

```powershell
flutter analyze
flutter test
```

```powershell
pytest -q
```
