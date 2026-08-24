# Smart Commuter Assistant+ Project Summary

This document is a repository-grounded technical summary of the current project state as of April 27, 2026. It is intended to support report writing, handover, and final submission documentation.

## 1. Project overview

Smart Commuter Assistant+ is a Flutter mobile application for rail commuters in the Klang Valley / Greater Kuala Lumpur area. The application combines:

- route planning across train lines,
- station and crowd forecasting views,
- user-submitted crowd and delay reports,
- offline caching of network data in SQLite,
- Supabase-hosted transport and crowd data,
- Python scripts for synthetic data generation, crowd-model training, and database upserts,
- an optional FastAPI mock backend for route-planning experiments.

The project is best described as a hybrid transit-assistance system rather than a pure ML system. Some outputs come from trained ML models, some come from rule-based heuristics, and some come from static or semi-static transit data.

## 2. Actual architecture in this repository

### 2.1 Frontend

The user-facing app is written in Flutter under `lib/`. The main navigation currently exposes four primary tabs:

- `Home`
- `Map`
- `Track`
- `Profile`

Additional screens exist for route planning, station lists, crowd forecast display, station crowd board display, login, signup, and station detail views.

### 2.2 Data backend

Supabase is the main operational backend. It stores:

- station metadata,
- route connection graph data,
- crowd reports,
- hourly crowd forecast rows,
- RPC functions for route search and crowd-report submission.

### 2.3 Python ML / forecasting layer

Python scripts under `scripts/` do four main jobs:

1. Generate synthetic crowd-labelled datasets.
2. Train a crowd-classification model.
3. Predict current crowd levels and insert them into Supabase.
4. Build hourly forecast rows and upsert them into Supabase.

### 2.4 Optional API backend

`backend/main.py` provides a FastAPI server with:

- `GET /health`
- `GET /plan-trip`

This backend is a mock / demo planner. It returns handcrafted sample route options, not a production routing engine.

## 3. What the app actually uses at runtime

There are two distinct "ML" paths in the project, and it is important to separate them in the report.

### 3.1 Server-side crowd classification model

The operational Python prediction script is `scripts/predict_and_upsert_crowd.py`.

That script:

- loads `crowd_predictor.pkl`,
- builds feature rows per stop,
- predicts `occupancy_level`,
- inserts results into Supabase table `crowd_reports`.

The hardcoded default model path in that script is:

- `scripts/crowd_predictor.pkl`

That means the default crowd classification model in active use by the Python pipeline is whatever is stored in `crowd_predictor.pkl`.

Repository inspection shows:

- `crowd_predictor.pkl` is a `RandomForestClassifier`
- `crowd_predictor_from_assistant.pkl` is also a `RandomForestClassifier`
- `crowd_predictor_lgbm_optuna10.pkl` exists as an experiment artifact, but it is not the default model loaded by the prediction pipeline

Conclusion:

- The classification model currently used by the prediction pipeline is `RandomForestClassifier`.
- LightGBM and XGBoost support were added for comparison / experimentation.
- Optuna is used for optional hyperparameter tuning, not as a replacement model.

### 3.2 Client-side in-app "ML" service

The Flutter app also contains `lib/services/commuter_ml_service.dart`.

This is not loading the Python `.pkl` file. Instead, it defines:

- synthetic sample generation,
- simple evaluation metrics,
- hard-coded feature scoring,
- hard-coded tree-like functions,
- route re-ranking logic.

This service behaves more like a deterministic heuristic ensemble for demo and ranking purposes than a deployed trained production model.

Conclusion:

- The mobile app does not directly run the trained Random Forest model.
- The app consumes forecast/report data from Supabase and also uses its own local heuristic ranking service.

## 4. Model training options in the repository

The training script is `scripts/train_crowd_model.py`.

It supports three classifier backends:

- `rf` -> `RandomForestClassifier`
- `lgbm` -> `lightgbm.LGBMClassifier`
- `xgb` -> `xgboost.XGBClassifier`

Default behavior:

- if no model is specified, it uses `SCA_MODEL=rf`
- therefore the default training backend is Random Forest

Optional behavior:

- `SCA_TUNE=true` enables Optuna-based hyperparameter tuning
- `SCA_TRIALS=<n>` controls the number of trials

Important interpretation:

- `Optuna` is not a model
- `Optuna` is a hyperparameter optimization framework
- `LightGBM` is a model family

So the correct comparison is not "Optuna vs LightGBM". The correct framing is:

- "LightGBM with Optuna tuning" versus
- "Random Forest with default or tuned parameters" versus
- "XGBoost with default or tuned parameters"

There is a committed tuned LightGBM artifact:

- `crowd_predictor_lgbm_optuna10.pkl.params.json`

The stored result in that file reports:

- `best_value = 0.85875`

This indicates that at least one Optuna-tuned LightGBM experiment was run and the best validation accuracy recorded in that tuning file was about `85.875%`.

However, the project does not currently switch the operational prediction script to that artifact. The deployed default remains `crowd_predictor.pkl`.

### 4.1 Crowd-classification comparison table

The following table separates what is implemented in code, what is actually deployed by default, and what measurable evidence exists in the repository.

| Backend | Implemented in training script | Default deployed model | Tuning support | Evidence in repo | Measured / recorded score | Interpretation |
| --- | --- | --- | --- | --- | --- | --- |
| Random Forest | Yes | Yes | Yes, via Optuna | `crowd_predictor.pkl`, training defaults in `train_crowd_model.py` | `85.45%` accuracy from local rerun on `simulated_crowd_data.csv` using current default split | Best report choice as the current production baseline because it is simple, present, and actually wired into `predict_and_upsert_crowd.py`. |
| LightGBM | Yes | No | Yes, via Optuna | `crowd_predictor_lgbm_optuna10.pkl`, `crowd_predictor_lgbm_optuna10.pkl.params.json` | `0.85875` best validation value recorded in saved Optuna artifact | Strong experimental candidate. Slightly better recorded score than the current Random Forest run, but not wired in as the default prediction artifact. |
| XGBoost | Yes | No | Yes, via Optuna | backend support present in `train_crowd_model.py` and backend test coverage in `tests/test_train_backends.py` | No committed metric artifact found in this repository snapshot | Experimental support exists, but there is not enough committed evidence to justify calling it better than the current baseline. |

Important wording for the final report:

- Random Forest is the current default model.
- LightGBM is the strongest documented experimental alternative in the repository.
- Optuna is the hyperparameter tuner, not a classifier.

## 5. Features used by the crowd classification model

The Python training pipeline uses:

- categorical:
  - `stop_id`
  - `route_id`
- numeric / engineered:
  - `hour`
  - `is_weekend`
  - `is_raining`
  - `is_holiday`
  - `peak_period`
  - `station_pressure`
  - `event_intensity`
  - `headway_minutes`

Preprocessing:

- `OneHotEncoder(handle_unknown="ignore")` for categorical fields
- numeric features passed through unchanged

Training pipeline structure:

- `ColumnTransformer`
- classifier backend
- wrapped in a `Pipeline`

## 6. How crowd labels are created

The crowd model is trained on synthetic labels, not on field-collected ground-truth labels.

The label-generation path is:

1. stop metadata loaded from `train_stops_kl.csv`
2. feature engineering from `crowd_feature_utils.py`
3. estimated occupancy percent computed by heuristics
4. occupancy percentage converted into `occupancy_level` from 1 to 5

The default occupancy thresholds are:

- `< 12` -> level 1
- `< 32` -> level 2
- `< 58` -> level 3
- `< 82` -> level 4
- `>= 82` -> level 5

This means the model is learning to reproduce a synthetic rule-based signal, not a real observed ridership label.

## 7. Synthetic data generation logic

Synthetic training data is generated primarily by:

- `generate_crowd_data.py`
- `generate_crowd_data_from_trends.py`

The feature heuristics come from `crowd_feature_utils.py`, which encodes:

- fixed Malaysian public holidays,
- route pressure scores,
- headway ranges by line and traffic bucket,
- station pressure tiers,
- event hotspot tiers,
- peak-period scoring,
- weather effect,
- interchange boosts,
- stop-specific bias,
- weekend / weekday effects,
- event intensity,
- ridership trend strength.

This is a strong simulation-oriented design. It is good for demos, prototyping, and controlled evaluation, but it is not equivalent to training on real AFC, GTFS-RT, AVL, or observed station crowd labels.

## 8. Does the project use LSTM or Prophet?

No.

Repository scan found no implementation of:

- LSTM
- GRU
- RNN
- Prophet
- Facebook Prophet / `prophet`

The current forecasting approach is not sequence-model-based.

### 8.1 What the project uses instead

For "current crowd" prediction:

- a tabular classifier trained on engineered features

For hourly forecast generation:

- heuristic forecast construction using ridership trend normalization and domain rules in `build_and_upsert_hourly_forecast.py`

For app-side route ranking:

- deterministic scoring logic in `commuter_ml_service.dart`

### 8.2 Does the project need LSTM?

Not urgently for submission.

An LSTM only makes sense if you have:

- a substantial time-indexed historical dataset,
- sequential station-level measurements,
- enough observations to justify temporal deep learning,
- a requirement to model temporal dependencies explicitly.

This repository currently relies mostly on synthetic or heuristic data. In that context, LSTM would likely add complexity without giving a defensible improvement for the report.

### 8.3 Does the project need Prophet?

Also not urgently.

Prophet is more appropriate when you have:

- real historical time-series data,
- trend + seasonality structure,
- stable timestamped measurements,
- a forecasting problem centered on temporal decomposition.

For this project's current stage, Prophet could be explored later for station-level hourly demand forecasting if real historical time series becomes available. It is not a necessary dependency to finish the current project coherently.

### 8.4 Report-friendly conclusion

For your current implementation, Random Forest plus engineered features is the more defensible choice than introducing LSTM or Prophet late in the submission cycle.

## 9. How hourly forecasting works

The hourly forecast generator is `scripts/build_and_upsert_hourly_forecast.py`.

This script does not load the trained Random Forest model.

Instead, it:

- reads ridership headline data,
- maps ridership columns to transit lines,
- computes normalized line-strength values,
- generates per-stop feature rows for each hour,
- estimates occupancy percentage through heuristics,
- converts that into:
  - `occupancy_level`
  - `expected_wait_minutes`
  - `eta_multiplier`
- upserts rows into `crowd_forecast_hourly`

Therefore:

- current operational "forecasting" is heuristic / trend-based
- current operational "classification" is model-based

This distinction matters in the final report.

## 10. Database design and Supabase role

The main SQL bootstrap file is:

- `scripts/manual_supabase_setup.sql`

Important database objects include:

- `transit_stops`
- `route_connections`
- `crowd_reports`
- `crowd_forecast_hourly`
- RPC function `find_route(start_stop, end_stop)`
- RPC function `submit_crowd_report(...)`

### 10.1 `transit_stops`

Purpose:

- normalized station / stop catalog for use across routing and reporting

### 10.2 `route_connections`

Purpose:

- directed edge list for the train network graph
- supports routing and interchange traversal

### 10.3 `crowd_reports`

Purpose:

- stores predicted and user-submitted crowd / delay reports

Observed source types in code include:

- `predicted`
- `user`
- `delay`
- `forecast+user`
- `user_blend`
- `closed_hours`
- `trend_model`
- fallback-like values such as `unknown` or `simulated`

### 10.4 `crowd_forecast_hourly`

Purpose:

- stores hour-level forecast rows per stop and weekend flag

Fields used in code include:

- `stop_id`
- `forecast_hour`
- `is_weekend`
- `occupancy_level`
- `occupancy_percent`
- `expected_wait_minutes`
- `eta_multiplier`
- `source_type`
- `updated_at`

### 10.5 RPCs

`find_route(...)`:

- recursive SQL search for route discovery
- acts as a database-side routing option

`submit_crowd_report(...)`:

- validates submitted crowd reports
- centralizes write handling

### 10.6 Security posture

The SQL enables row-level security and creates read policies. For a school project, this is fine. For production, the policies should be reviewed and tightened.

## 11. Flutter app service architecture

Key frontend services include:

- `TransitNetworkService`
- `CrowdReportsService`
- `TransitPlannerService`
- `CommuterMlService`
- `DatabaseService`
- `AuthService`
- `ActiveTripService`
- `NotificationService`
- `ThemeController`

### 11.1 `TransitNetworkService`

Responsibilities:

- fetch stop metadata from Supabase table `train_stops_kl`
- fetch route edges from `route_connections`
- cache both locally in SQLite
- build fallback route connections if DB edge data is missing
- expose grouped station options for UI search

This service includes both in-memory caching and in-flight request reuse.

### 11.2 `CrowdReportsService`

Responsibilities:

- fetch latest crowd reports
- fetch hourly forecast rows
- blend forecast values with recent user reports
- cache forecast, nearest-station, and station-board lookups with short TTLs
- expose service-status signals such as cached forecast, blended live data, and fallback sources
- compute closed-hours behavior
- provide nearest-station crowd queries
- provide station-board and display-feed views

This is one of the core orchestration services in the app.

### 11.3 `TransitPlannerService`

Responsibilities:

- obtain route candidates from a planning gateway
- rank them using `CommuterMlService`
- produce a final plan result including origin crowd/delay estimate

Gateway types supported:

- local graph-backed planner
- HTTP API planner
- resilient planner with fallback

### 11.4 `CommuterMlService`

Responsibilities:

- simulate prediction of delay minutes
- simulate crowd class
- rank routes using crowd and transfer penalties

Important note:

- this service is not loading the trained Python Random Forest artifact
- it is an internal scoring engine written directly in Dart

### 11.6 `AuthService`

The app now uses Supabase Auth for sign-up, login, logout, and session restoration.

To preserve the rest of the app's local storage features, the authenticated Supabase user is mirrored into a local SQLite profile row. That means:

- authentication is handled by Supabase
- app preferences / history / favorites can still use local integer `user_id` records
- the login and signup screens are no longer based on local demo-only password checks

### 11.5 `DatabaseService`

Local SQLite tables include:

- `users`
- `user_preferences`
- `favorite_routes`
- `recent_searches`
- `travel_history`
- `offline_cache`
- `cached_train_stops`
- `cached_route_connections`

This means the project already includes meaningful local persistence, not just remote database usage.

## 12. Routing approach

Routing is currently hybrid.

Available mechanisms:

1. local graph enumeration in Flutter
2. optional mock FastAPI planner
3. SQL RPC route search in Supabase

In practice, the app's route-planning layer is closer to graph-based route generation plus heuristic re-ranking than to a real-time GTFS-aware routing engine.

## 13. Use of Docker in this project

Docker is present, but its role is limited and specific.

Files:

- `docker-compose.yml`
- `docker/python-worker/Dockerfile`
- `Makefile`

### 13.1 What Docker is used for

Docker packages the Python worker environment so that the ML / forecast scripts can run in a reproducible container with the required Python dependencies installed.

This is useful for:

- avoiding local dependency mismatch,
- standardizing Python execution across machines,
- running model / forecast jobs without manually recreating the environment.

### 13.2 What Docker is not currently doing

Docker is not currently the main deployment path for:

- the Flutter app,
- the FastAPI backend,
- the full end-to-end system stack.

### 13.3 Current compose behavior

The checked-in `docker-compose.yml` runs:

- `python scripts/build_and_upsert_hourly_forecast.py --dry-run`

That means the current compose file is set up more as a worker/test harness than a production runtime.

### 13.4 Report-friendly conclusion

For this project, Docker's value is:

- reproducible execution of Python ML and forecast scripts
- easier environment setup for development and demonstration

It is not essential to the Flutter app itself, but it is useful for the backend data-processing side.

## 14. Current testing coverage

Python test files present:

- `tests/test_crowd_feature_utils.py`
- `tests/test_train_backends.py`
- `tests/test_train_crowd_model.py`

Flutter test file present:

- `test/widget_test.dart`

Current emphasis is stronger on the Python modeling utilities than on Flutter widget / integration test coverage.

## 15. Current implementation limitations

The most important technical limitations are:

1. The core training labels are synthetic.
2. The app-side ML and server-side ML are separate systems.
3. The FastAPI backend is graph-backed and no longer returns only handcrafted demo routes, but it is still a lightweight local planner rather than a GTFS-grade production routing engine.
4. Forecast generation is heuristic rather than model-driven.
5. There is no real-time transit feed integration yet.
6. There is no real observed passenger-count dataset in the repository.
7. Security and operational hardening are still development-oriented.

## 16. Performance and loading behavior

### 16.1 What was slowing page loading

Two user-visible issues were identified in the navigation shell:

1. the main tab switch flow added an artificial loading phase with a timer
2. tab content was being rebuilt instead of being kept alive across tab switches

This made page changes feel slower than necessary even when data was already available.

### 16.2 Improvement applied

The navigation shell in `lib/main.dart` was updated so that:

- tab pages are preserved using `IndexedStack`
- the artificial tab-switch loading transition was removed from main navigation
- Supabase config now comes from build-time `--dart-define` values instead of hardcoded credentials
- noncritical startup initialization is deferred behind an app bootstrap gate after `runApp()`

This should improve perceived responsiveness when changing pages.

### 16.3 Other likely loading bottlenecks still present

There are still several real data-loading costs:

- the bootstrap gate still performs multiple async initializers before the authenticated shell becomes interactive
- several screens fetch Supabase data in `initState()`
- some screens request large forecast datasets for many stops
- crowd and network data are fetched by multiple screens independently
- some pages use heavy `FutureBuilder`-driven first paint flows

### 16.4 Next performance wins to prioritize

If more optimization time is available, the next best changes are:

1. Preload shared network / forecast data once at app shell level.
2. Reduce first-authenticated-screen wait time by splitting bootstrap into critical and background phases.
3. Broaden cache reuse across more crowd and routing queries.
4. Reduce full-screen loading animations to only genuinely slow paths.
5. Batch and reuse station metadata instead of screen-by-screen refetching.

## 17. Suggested improvements for the final report and project quality

High-value improvements, ordered by practicality for a near-term submission:

1. Make the architecture distinction explicit:
   The app uses a Random Forest crowd classifier in the Python pipeline, but the Flutter app also contains a separate deterministic route-ranking engine.

2. Present Optuna correctly:
   Describe it as hyperparameter tuning for LightGBM / XGBoost / Random Forest, not as a separate competing model.

3. Add one model-comparison table:
   Compare Random Forest, LightGBM, and XGBoost on the same validation split and clearly state why the deployed default remained Random Forest.

4. Add one system-flow diagram:
   Flutter app -> Supabase -> Python worker -> forecast/report tables -> app display.

5. State the synthetic-data limitation directly:
   This will strengthen the report because it shows methodological honesty.

6. Add a future-work section:
   Real GTFS/GTFS-RT ingestion, true ridership labels, stronger evaluation, and model retraining automation.

7. Expand Flutter testing if time allows:
   Even a few focused service/widget tests would improve submission quality.

8. Separate "forecasting" from "classification" in the write-up:
   Your current project does both, but by different mechanisms.

## 18. Can everything be finished by April 30, 2026?

Today in this workspace is April 27, 2026, so you effectively have about three days before April 30, 2026.

Yes, finishing a solid submission by April 30 is realistic if you prioritize correctly. No, it is not realistic if you try to add a brand-new forecasting paradigm such as LSTM or Prophet now.

### 18.1 What is realistic by April 30

- finalize documentation,
- verify and polish the current architecture,
- clean up performance issues,
- add a short evaluation / comparison section,
- tighten the presentation of the methodology,
- fix a few visible UX rough edges,
- run and capture test evidence,
- produce screenshots and system diagrams for the report.

### 18.2 What is risky by April 30

- replacing the whole modeling approach,
- introducing real-time external transport APIs,
- adding a brand-new deep learning forecasting pipeline,
- redesigning the backend architecture,
- attempting major schema or product pivots.

### 18.3 Recommended submission strategy

Treat this as a strong prototype / decision-support system submission with:

- clear architecture,
- a justified Random Forest baseline,
- documented LightGBM / Optuna experiments,
- honest limitations,
- practical future work.

That is far more defensible than trying to force one more complicated model into the project at the last minute.

## 19. Key files to cite in the report

- `lib/main.dart`
- `lib/services/transit_network_service.dart`
- `lib/services/crowd_reports_service.dart`
- `lib/services/transit_planner_service.dart`
- `lib/services/commuter_ml_service.dart`
- `lib/services/database_service.dart`
- `scripts/crowd_feature_utils.py`
- `scripts/generate_crowd_data.py`
- `scripts/generate_crowd_data_from_trends.py`
- `scripts/train_crowd_model.py`
- `scripts/predict_and_upsert_crowd.py`
- `scripts/build_and_upsert_hourly_forecast.py`
- `scripts/manual_supabase_setup.sql`
- `backend/main.py`
- `docker-compose.yml`
- `docker/python-worker/Dockerfile`
- `tests/test_train_backends.py`

## 20. Recent additions (July 2026)

The following features were added after the initial April 2026 submission scope:

### 20.1 Schematic Transit Map
- `assets/data/map_stations.json` — percentage-based (x,y) coordinate data for 24 Klang Valley stations mapped to the static `klang_valley_map.png` asset
- `lib/widgets/schematic_transit_map.dart` — InteractiveViewer-based map with tappable station circles, origin/destination selection, route line highlighting via CustomPainter, and bottom sheet actions
- The schematic view replaces the previous geo-projected station overlay that did not align with the static image
- Station markers use route-aware colors; when a route is selected, non-selected lines grey out

### 20.2 FastAPI Backend Enhancements
- **GTFS Static Feed Integration** (`backend/gtfs_service.py`): Downloads official Malaysia rapid-rail-kl GTFS zip from `api.data.gov.my` with 24-hour cache. Parses `stops.txt`, `routes.txt`, `trips.txt`, `stop_times.txt`, `calendar.txt`, and `frequencies.txt` to calculate scheduled arrivals
- **`GET /arrivals/station/{stop_id}`**: Returns next N scheduled arrivals with minutes-until calculation
- **`GET /arrivals/nearest`**: Nearest station lookup by GPS + arrivals
- **`POST /crowd/report`**: Geo-fenced (500m), rate-limited (2h), consensus-checked report submission
- **`GET /crowd/blend`**: Returns time-decay blended crowd level from the SQL function
- **`backend/crowd_service.py`**: Validation service with Haversine distance, rate-limit checks against Supabase, consensus corroboration logic

### 20.3 Time-Decay Crowd System (Supabase)
- `supabase/migration_crowd_system.sql`:
  - `historical_crowds` table — daily snapshots of blended crowd levels per stop/hour/weekday
  - `get_blended_crowd_level()` SQL function — 40% ML forecast + 60% age-weighted user reports (2h window), fallback to 14-day historical moving average
  - `submit_crowd_report()` updated with rate-limiting and consensus checks
  - `snapshot_daily_blend()` — cron-ready function for midnight snapshots
- `supabase/rls_policies.sql` hardened: crowd_reports INSERT requires `authenticated` role (anon removed)

### 20.4 Geo-Fencing (Flutter)
- `lib/screens/stations_screen.dart`: Report submission bottom sheet checks GPS distance to station. If >500m, warning displayed and submit button disabled with "Move Closer to Submit" label
- `lib/services/crowd_reports_service.dart`: Tries FastAPI backend first (with lat/lng) for validated submission, falls back to Supabase RPC

### 20.5 UI Polish
- Flutter debug banner removed via `debugShowCheckedModeBanner: false`
- WIP badge (hammer icon + "W.I.P") added to `AppPageTitle` widget, visible on every app page
- Production backend URL added to `BackendConfigService` defaults

## 21. Final technical conclusion

The current repository is centered on a Random Forest crowd-classification pipeline trained on engineered synthetic data, supported by optional LightGBM / XGBoost experimentation and Optuna tuning. The deployed prediction path still points to the Random Forest artifact. The project does not use LSTM or Prophet, and neither is necessary to make the present submission coherent. The hourly forecast system is rule-based and trend-driven rather than sequence-model-driven. Docker is useful here as a reproducible container for the Python worker environment, not as the main runtime for the Flutter app. With focused prioritization over the remaining time before April 30, 2026, the project can be submitted in a defensible and technically consistent form.
