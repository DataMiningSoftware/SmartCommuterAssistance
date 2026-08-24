# Agent Rules — Smart Commuter Assistant+

## Config & env files
- Check ALL subdirectories when searching for config or env files (env/, config/, .config/ etc.)
- Config is in `env/dev.json` (JSON format, NOT .env)
- Always use recursive globs like `**/*.env*`, `**/*.json`, `**/*.yaml`

## Project structure
- Flutter app in `app/`
- Backend in `backend/` (FastAPI)
- Python scripts (ML training, data gen, SQL) in `scripts/`
- Supabase migrations in `supabase/`

## Database
- Supabase (PostgreSQL) with tables: transit_stops, route_connections, crowd_reports, crowd_forecast_hourly, historical_crowds
- SQLite local cache for offline (sqflite)

## Build & run
- Flutter: `cd app && flutter run --dart-define-from-file=env/dev.json`
- Backend: `cd backend && uvicorn main:app --reload`
- Flutter tests: `cd app && flutter test`
- Python tests: `pytest tests/`
- Dart analyze: `cd app && dart analyze lib/`

## Coding conventions
- No comments in code unless explicitly asked
- Use existing route_colors.dart for line colors (KJ=#E34262, MRT=#007A4D, etc.)
- Crowd levels: 1=Empty, 2=Light, 3=Moderate, 4=Heavy, 5=Crowded
- State management: ValueNotifier + ValueListenableBuilder (no Provider/Riverpod)
- Pathfinding: Dijkstra with 8-min line-transfer penalty
- Route line IDs: KJ, MRT, PYL, AG, PH, MR, BRT

## Milestone ETA Architecture (Pin & Countdown)
- ETA is **pinned once** when GPS proximity (<100m) to origin station is reached
- Display = `(pinnedArrivalTime - now).inMinutes` — steady countdown, no jitter
- Re-pin only on: delay report (+N min), crowd report (+extra wait), reroute (fresh pin)
- Background forecast refreshes never touch the displayed ETA
- On arrival: submit `trip_feedback` {predicted, actual, deviation} to DB for ML training
- Walking time to origin station is included in the base estimate (80m/min pace)
- Tables: `trip_feedback` stores actual-vs-predicted per trip for ML retraining

## Map Page Architecture
- Two views: **Transit map** (default) and **Geographic map**, toggled via SegmentedButton
- **Transit map** (`InteractiveSchematicMap` in `lib/widgets/interactive_schematic_map.dart`):
  - Background: `assets/images/klang_valley_map.jpeg` (1692x2400) drawn scaled-to-fit
  - Fallback: gray canvas with colored transit lines always rendered on top
  - Station dots: white circles with black border, interchanges slightly larger
  - Selected stations: amber/orange pulsing via 900ms AnimationController
  - Route highlight: thick (6px) colored polylines with blinking alpha (0.6→1.0), drawn on top of dimmed (0.3 alpha) background lines
  - Tap handling: hit test within 18px radius, maps pixel coords to grid positions via `_toPixel`
- **Geographic map** (`FlutterMap` with CartoDB `light_all` tiles):
  - Station markers: white dots with name labels (shown when zoom >= 14)
  - Colored polylines per line, dimmed (0.15) when no route, highlighted (1.0) on route
  - 82 of 233 stations have real lat/lng coordinates in `assets/data/transit_network.json`
  - Coordinates loaded from TransitGraph first, network stops as fallback
- **Both views** share `MapSelectionController` (station selection, route planning) and `StationOrRouteCard`
- **Hidden lines** (not calibrated): KTM (IDs 1,2,10), KLIA (6,7), Johan Setia (11) — filtered via `_hiddenLineIds` in `map_screen.dart`
- Station positions from `assets/schematic_layout.json` (100x140 grid, extracted from the JPEG)

## Daily Retrain Pipeline
- `aggregate_training_data.py` — pulls real `crowd_reports` from Supabase, groups by (stop_id, hour, day_of_week), builds feature matrix
- `run_daily_pipeline.py` — orchestrator: aggregate → train (`train_crowd_model.py`) → predict+upsert (`predict_and_upsert_crowd.py`)
- Run manually: `cd scripts && python run_daily_pipeline.py`
- Requires env vars: `SUPABASE_URL`, `SUPABASE_SERVICE_KEY`
- Output: `crowd_forecast_hourly` table in Supabase with real data predictions
- The upsert now includes `expected_wait_minutes` and `eta_multiplier` per level (1→2,4,6,8,10 wait & 1.0,1.05,1.12,1.22,1.35 multiplier)
