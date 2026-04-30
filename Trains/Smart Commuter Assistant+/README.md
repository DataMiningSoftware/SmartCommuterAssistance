# Smart Commuter Assistant+

Smart Commuter Assistant+ is a Flutter application for Klang Valley rail commuters. It combines station lookup, route planning, crowd forecasts, rider reports, local trip history, and an optional FastAPI planner backend into one mobile-first experience.

The repository contains:

- A Flutter app with Supabase authentication and local SQLite caching.
- Supabase SQL setup scripts for station catalogs, route connections, crowd reports, and hourly forecasts.
- Python scripts for synthetic crowd data generation, model training, report graphs, and forecast upserts.
- A lightweight FastAPI backend that can serve route candidates to the Flutter app.
- Docker and CI configuration for repeatable Python worker and test workflows.

## Features

- Supabase email/password sign up and login.
- Route planning across Klang Valley rail stops with interchange handling.
- Optional backend route planning with local graph fallback in the app.
- Crowd forecast board with hourly occupancy levels.
- Rider-submitted crowd and delay reports.
- Nearby station crowd forecast lookup.
- Zoomable Klang Valley rail map.
- Favorite routes, recent searches, travel history, preferences, and theme settings.
- Offline cache for transit stops and route connections.

## Tech Stack

- Flutter & Dart 3 — mobile UI and cross-platform codebase.
- Supabase — Auth, Postgres, realtime; client uses anon key for apps.
- Local cache: SQLite via `sqflite`.
- Backend: FastAPI + Uvicorn (optional route planner).
- Python ML stack: pandas, numpy, scikit-learn, LightGBM, XGBoost, Optuna.
- Containerization & worker: Docker and Docker Compose.
- CI & tooling: GitHub Actions, `flutter analyze`, `black`, `flake8`, `pytest`.
- Platform tools: Android Studio / AVD, `adb` (Android); Xcode (macOS) for iOS.

## Quick Start (How to run the project)

Use these steps to run the main Flutter app for submission or local testing.

1. Install Flutter dependencies:

```powershell
flutter pub get
```

2. Run the app using the included Supabase development config:

```powershell
flutter run --dart-define-from-file=env/dev.json
```

3. If the app needs the optional route-planning backend, start it in another terminal:

```powershell
cd backend
.\run_backend.ps1
```

The backend runs at `http://127.0.0.1:8000`. Android emulators should use `http://10.0.2.2:8000`, which is already available as a backend URL preset inside the app.

Docker is optional and is only needed if you want to run the Python forecast worker in a container.

## Repository Layout

```text
.
|-- .github/workflows/              # Flutter and Python CI workflows
|-- android/                        # Android Flutter project
|-- assets/                         # App images and map assets
|-- backend/                        # Optional FastAPI route-planning backend
|-- docker/python-worker/           # Dockerfile for Python forecast worker
|-- env/                            # Local Dart define JSON files
|-- lib/
|   |-- constants/                  # Shared app colors, shadows, crowd levels
|   |-- main.dart                   # Flutter entry point
|   |-- models/                     # App data models
|   |-- screens/                    # Main app screens
|   |-- services/                   # Auth, Supabase, local DB, routing, ML services
|   |-- widgets/                    # Shared UI widgets
|   `-- PythonScript/               # SQL setup, data generation, model training scripts
|-- report_assets/                  # Generated charts for model/report documentation
|-- test/                           # Flutter widget tests
|-- tests/                          # Python tests
|-- web/                            # Flutter web shell
|-- docker-compose.yml              # Python worker compose service
|-- Makefile                        # Python helper targets
|-- Project_Summary.md              # Project report/summary notes
|-- pubspec.yaml                    # Flutter dependencies and assets
|-- requirements.txt                # Python ML/worker dependencies
`-- requirements-dev.txt            # Python development/test dependencies
```

## Prerequisites

- Flutter SDK with Dart 3.
- Android Studio, Android SDK, or another Flutter-supported target.
- Python 3.10 or newer.
- A Supabase project.
- Docker Desktop, optional.

## Environment Setup

Python scripts and the Docker worker read environment variables from your shell or from a `.env` file:

```powershell
Copy-Item .env.example .env
```

Fill in the Supabase values:

```text
SUPABASE_URL=https://your-project.supabase.co
SUPABASE_SERVICE_KEY=your-service-role-key
SUPABASE_ANON_KEY=your-anon-key
MLFLOW_TRACKING_URI=
GLOBAL_EVENT_LEVEL=0.0
STOP_IDS=
```

The Flutter app reads Supabase values from Dart defines, not from `.env`.
This repository includes `env/dev.json` for local development, so collaborators can use the configured Supabase project URL and anon key if they have permission to work against your development database.

You can pass them inline:

```powershell
flutter run `
  --dart-define=SUPABASE_URL=https://your-project.supabase.co `
  --dart-define=SUPABASE_ANON_KEY=your-anon-key
```

Or use a JSON define file such as `env/dev.json`:

```powershell
flutter run --dart-define-from-file=env/dev.json
```

The Supabase anon key is expected to be used by client apps, but the database must be protected with Row Level Security policies. Do not put a Supabase service-role key in Flutter Dart defines or ship it with the app.

## Supabase Database Setup

Create or import `public.train_stops_kl` first. The source CSV used by backend and scripts is:

```text
lib/PythonScript/train_stops_kl.csv
```

Then run these SQL scripts from `lib/PythonScript/` in order:

1. `stop_catalog_setup.sql`
2. `route_connections_setup.sql`
3. `find_route_rpc_setup.sql`
4. `crowd_reports_setup.sql`
5. `crowd_forecast_setup.sql`

Optional seed or migration scripts:

- `randomized_crowd_predictions_seed.sql`
- `migrate_crowd_scale_to_five_levels.sql`
- `manual_supabase_setup.sql`
- `insert_connections.sql`

The app expects these main Supabase objects:

- `train_stops_kl`
- `transit_stops`
- `route_connections`
- `crowd_reports`
- `crowd_forecast_hourly`
- RPC functions such as `get_unique_stations` and `submit_crowd_report`

## Run the Flutter App

Install Flutter packages:

```powershell
flutter pub get
```

Quick local run (uses `env/dev.json` by default):

```powershell
flutter run --dart-define-from-file=env/dev.json
```

Example `env/dev.json` (used with `--dart-define-from-file`):

```json
{
  "SUPABASE_URL": "https://your-project.supabase.co",
  "SUPABASE_ANON_KEY": "your-anon-key",
  "BACKEND_URL": "http://127.0.0.1:8000"
}
```

If you prefer inline values:

```powershell
flutter run --dart-define=SUPABASE_URL=https://your-project.supabase.co --dart-define=SUPABASE_ANON_KEY=your-anon-key
```

Running on an Android emulator (Android Studio)

- Start an AVD in Android Studio (Tools → AVD Manager → Launch), or use:

```powershell
flutter emulators
flutter emulators --launch <emulatorId>
```

- If your backend runs on your host machine (for example `http://127.0.0.1:8000`), the Android emulator should use `http://10.0.2.2:8000`. Example:

```powershell
flutter run --dart-define=SUPABASE_URL=https://your-project.supabase.co --dart-define=SUPABASE_ANON_KEY=your-anon-key --dart-define=BACKEND_URL=http://10.0.2.2:8000
```

Running on a physical Android device (USB or wireless)

- Enable Developer options and USB debugging on the device and connect via USB (or set up wireless debugging).
- Verify the device is visible:

```powershell
flutter devices
adb devices
```

- For a local backend use either:
  - the host machine LAN IP (example `http://192.168.1.5:8000`) and ensure the phone is on the same network, or
  - use `adb reverse tcp:8000 tcp:8000` to forward the device port to your host and keep the device connected.

Example run using the host LAN IP:

```powershell
flutter run --dart-define=SUPABASE_URL=https://your-project.supabase.co --dart-define=SUPABASE_ANON_KEY=your-anon-key --dart-define=BACKEND_URL=http://192.168.1.5:8000
```

Supabase URL and anon key

- The app requires `SUPABASE_URL` and `SUPABASE_ANON_KEY` as Dart defines. Do not place a Supabase service-role key in client-side defines.
- Pass them via `env/dev.json` (`--dart-define-from-file`) or inline with `--dart-define`.

iPhone / iOS limitations

- Building for iOS requires macOS and Xcode; you cannot build iOS apps from Windows or Linux.
- Running on a physical iPhone requires app signing and provisioning via Xcode (Apple developer account or personal team).
- The iOS Simulator (on macOS) can reach a host-local backend via `http://localhost:8000`. A physical iPhone cannot access `localhost` on your machine — use the host LAN IP or a tunnel (for example `ngrok`) instead.
- iOS enforces App Transport Security (ATS). If your local backend uses plain HTTP you may need to add an exception to `ios/Runner/Info.plist` or use HTTPS for testing.

The app shows a configuration error if `SUPABASE_URL` or `SUPABASE_ANON_KEY` is missing.

## Optional Backend

The backend exposes route planning and health endpoints. It reads stop data from:

```text
lib/PythonScript/train_stops_kl.csv
```

Start it on Windows:

```powershell
cd backend
.\run_backend.ps1
```

Or run it manually:

```powershell
cd backend
python -m pip install -r requirements.txt
python -m uvicorn main:app --reload --host 0.0.0.0 --port 8000
```

Useful endpoints:

- `GET http://127.0.0.1:8000/health`
- `GET http://127.0.0.1:8000/docs`
- `GET http://127.0.0.1:8000/plan-trip?origin=KL%20Sentral&destination=Kajang&departure=2026-03-02T10:00:00&maxRoutes=4`

Flutter backend URL presets:

- Android emulator: `http://10.0.2.2:8000`
- Localhost/iOS simulator/desktop: `http://127.0.0.1:8000`
- Physical phone: use your computer LAN IP, for example `http://192.168.1.5:8000`

The Flutter route planner can call the backend and fall back to local graph routing if the backend is unavailable.

## Python ML and Forecasting

Install Python dependencies:

```powershell
python -m pip install --upgrade pip
pip install -r requirements.txt
pip install -r requirements-dev.txt
```

Generate synthetic crowd data:

```powershell
python lib/PythonScript/generate_crowd_data.py --rows 10000 --output lib/PythonScript/simulated_crowd_data.csv
```

Train the default RandomForest model:

```powershell
python lib/PythonScript/train_crowd_model.py --input lib/PythonScript/simulated_crowd_data.csv --output lib/PythonScript/crowd_predictor.pkl
```

Train with LightGBM:

```powershell
$env:SCA_MODEL = "lgbm"
python lib/PythonScript/train_crowd_model.py --input lib/PythonScript/simulated_crowd_data.csv --output lib/PythonScript/crowd_predictor_lgbm.pkl
```

Run Optuna tuning:

```powershell
$env:SCA_MODEL = "lgbm"
$env:SCA_TUNE = "true"
$env:SCA_TRIALS = "50"
python lib/PythonScript/train_crowd_model.py --input lib/PythonScript/simulated_crowd_data.csv --output lib/PythonScript/crowd_predictor_tuned.pkl
```

Build or test forecast upserts:

```powershell
python lib/PythonScript/build_and_upsert_hourly_forecast.py --dry-run
```

Generate report charts:

```powershell
python lib/PythonScript/generate_classification_graphs.py
```

Generated charts are stored under `report_assets/classification_graphs/`.

## Docker Worker

Build and run the Python worker through Docker Compose:

```powershell
docker compose build
docker compose run --rm python-worker
```

The default compose command runs:

```text
python lib/PythonScript/build_and_upsert_hourly_forecast.py --dry-run
```

The Makefile also has direct Docker targets:

```powershell
make docker-build
make docker-run
```

## Tests and Quality Checks

Flutter checks:

```powershell
flutter analyze
flutter test
```

Python checks:

```powershell
pytest -q
black --check .
flake8 .
```

Makefile shortcuts:

```powershell
make install-dev
make test
make lint
make generate
make train
```

GitHub Actions workflows are available in `.github/workflows/` for Flutter analysis/tests and Python lint/tests.

## Notes

- Supabase service-role keys are only for trusted Python scripts, backend jobs, or worker jobs.
- The app caches transit stops and route connections locally so route planning can continue with the latest successfully loaded data.
- The backend planner is optional; the app includes local route fallback behavior.
- Some CSV, model, and chart files in `lib/PythonScript/` and `report_assets/` are generated artifacts and can be regenerated from the scripts.
- `backend/README.md` contains backend-specific quick-start notes.

## Rights

Muahammad Nawfal Bin Nadzrim
