# Smart Commuter Assistant+ — Deployment Checklist

<!--
  How to use:
  1. Mark [ ] → [x] as items are completed
  2. Add new items above "Uncategorized" as they come up
  3. Commit and push after every meaningful change
-->

## 1. Data Quality — Station Names & Coordinates

- [ ] Strip corporate naming-rights suffixes from `transit_network.json` station names (` - REDONE`, `BANK RAKYAT `, `CGC `, ` - UOB`, ` - MAYBANK`, ` - THE FACE STYLE`, etc.) — ~20 stations affected
- [ ] Fix hyphen spacing: `SOUTH QUAY-USJ 1` → `SOUTH QUAY - USJ 1`, `SUNWAY-SETIA JAYA` → `SUNWAY - SETIA JAYA`
- [ ] Fix spelling: `KENTOMEN` → `KENTONMEN`
- [ ] Verify name-matching passes for all 204 schematic stations (no "appended at end" stations in coverage logs)
- [ ] Populate real `lat`/`lng` for all 233 stations in `transit_network.json` (currently all `0,0`)
- [ ] Verify Supabase `train_stops_kl` table has complete coordinate coverage
- [ ] Verify geographic map markers render for all stations

## 2. AI / ML Model

**Current architecture:** Two-tier. Server-side = sklearn RandomForest (13 features incl. day_of_week cyclical encoding) trained on synthetic (fake) data. Client-side = 5 decision stumps + 3 linear scorers (placeholder).

**Problem:** Synthetic data is generated once and never updated. Real `crowd_reports` and `trip_feedback` rows accumulate in DB but are never fed back into the model.

### Real-data pipeline (priority)
- [ ] Write Python script `aggregate_training_data.py` that:
  - Pulls real `crowd_reports` (last 90 days) grouped by (stop_id, hour, day_of_week)
  - Pulls `trip_feedback` deviation aggregates per (route_id, hour, day_of_week)
  - Pulls weather history (Open-Meteo API) per day
  - Outputs feature matrix with 15+ real features
- [ ] Set up daily cron (GitHub Actions or backend scheduler) to:
  - Run `aggregate_training_data.py`
  - Retrain RandomForest on real data
  - Run `predict_and_upsert_crowd.py` to write fresh forecasts to `crowd_forecast_hourly`
- [ ] Add weather as a feature: fetch Open-Meteo forecast at trip start, attach to `trip_feedback`
- [ ] Add holiday calendar as a feature (public holidays affect crowd patterns)
- [ ] After 3 months of real hourly history: evaluate Prophet as parallel time-series forecast pipeline (keep RandomForest for short-term, Prophet for 24–72h ahead)

### On-device inference
- [ ] Replace `CommuterMlService` (5 simulated stumps) with ONNX export of trained sklearn model for server–client consistency
- [ ] Run lightweight inference on Flutter side for instant crowd predictions without network

### Endpoints
- [ ] Add `GET /crowd/forecast` endpoint to backend for future Prophet output
- [ ] Pipe GTFS-derived headway-by-day-by-hour as a real-time feature (schema ready, not yet wired)

## 3. Train Arrivals

**Architecture:** Three-tier — FastAPI backend (`/arrivals/station/{id}`) → local bundled GTFS JSON (`assets/data/gtfs_schedule.json`) → "No scheduled trains found". Backend downloads Malaysia official GTFS static feed, parses calendar (day-of-week aware) + frequencies (headway-based). UI shows CRT-style countdown that ticks in real-time.

- [x] CRT-style countdown with 1-second ticker (Timer.periodic — `scheduled_arrivals_panel.dart`)
- [ ] Deploy FastAPI backend to Render (needed for GTFS arrivals)
- [ ] Verify `/arrivals/station/{id}` returns correct next-N arrivals
- [ ] Verify offline fallback loads from bundled JSON when backend is down

## 4. DB Migration (Day-of-Week Crowd Prediction)

- [ ] Run `supabase/migration_day_of_week.sql` in Supabase SQL Editor
- [ ] Regenerate training data: `python generate_crowd_data.py --rows 50000`
- [ ] Retrain model: `python train_crowd_model.py --model rf`
- [ ] Run inference: `python predict_and_upsert_crowd.py`
- [ ] (Optional) Update script to loop day_of_week 0–6 for full 168-slot pre-generation

## 5. Real-Time Train Tracking (Crowd-Sourced GPS)

**Goal:** Replace static GTFS schedule with live train positions using anonymized GPS reports from users riding the train.

### Phase 1 — Backend core
- [ ] Add `train_positions` in-memory store (Redis or dict) + `POST /train/position` endpoint
- [ ] Implement trip matching: user lat/lng → nearest GTFS `trip_id` + direction
- [ ] Interpolate arrival estimate: current position + recent speed → ETA per upcoming stop
- [ ] Update `/arrivals/station/{id}` to blend real-time positions with schedule fallback
- [ ] Add `/train/map` endpoint returning all active train positions (for map overlay)

### Phase 2 — Flutter app
- [ ] Add `geolocator` package + location permission flow (iOS Info.plist, Android permissions)
- [ ] Implement rail-corridor detection: speed 20–80 km/h + proximity to track geometry
- [ ] Periodic position upload every 5–10s while on-train (throttled, battery-aware)
- [ ] Background location service for continued tracking when app is minimized
- [ ] Add privacy notice / opt-in screen explaining anonymous GPS collection

### Phase 3 — Tunnel fallback
- [ ] Detect GPS loss (tunnels, underground sections) → interpolate from last known speed + schedule
- [ ] Resume tracking when GPS reacquires above ground

### Phase 4 — Delay reporting (lightweight alternative)
- [ ] Add "Report delay" button to arrivals panel (no GPS needed)
- [ ] Backend logs actual vs scheduled → builds delay distribution per line/hour/day
- [ ] Apply learned delay offset to static schedule → "typically 2 min late at this hour"

## 6. UI / UX

- [ ] Add loading skeleton/shimmer states on all data screens (replace partial-flash)
- [ ] Add pull-to-refresh on: Stations, CrowdBoard, Forecast, Map screens
- [ ] Show full-screen "No internet" offline state (not just a banner)
- [ ] Add client-side rate-limit indicator on crowd report button (grey out for 2h)
- [x] Add attribution notices: CartoDB, Open-Meteo, data.gov.my
- [ ] Add haptic feedback on crowd report submission
- [ ] Add semantic labels to schematic map stations (accessibility / TalkBack)
- [ ] Verify schematic map renders all lines with correct colors (KJ=#E34262, MRT=#007A4D, etc.)
- [ ] Verify geographic map tiles load from OpenStreetMap
- [ ] Test on low-end Android device / Android emulator with 2x CPU throttling

## 7. Security & Operations

- [x] `env/` added to `.gitignore`, `env/dev.json` untracked
- [x] Real keys scrubbed from `.env.example`
- [x] Rotate Supabase service_role key (old one exposed in git history)
- [ ] Verify RLS policies on all Supabase tables (anon key should only have minimum permissions)
- [ ] Enable Android ProGuard / R8 minification for release (`flutter build appbundle --release`)
- [ ] Add app icon (adaptive icon for Android)
- [ ] Add splash screen / launch screen
- [ ] Add app version + build number to settings/about page
- [ ] Review Sentry dashboard for crashes after first deployment week
- [ ] Add basic page-view analytics (Sentry performance or similar)
- [ ] Rate-limit report endpoint on backend (prevent abuse beyond 2h cooldown)

## 8. Testing

- [ ] Run `dart analyze lib/` — zero errors, zero warnings
- [ ] Run `flutter test` — all pass
- [ ] Run Python tests (`pytest tests/`)
- [ ] Manual smoke test: auth → browse stations → view crowd board → submit report → plan route → view map → toggle theme
- [ ] Test offline: disable network, verify SQLite cache serves stops + routes

## 9. Milestone-Based ETA (Pin & Countdown)

**Goal:** Replace jittery ETA (changes every 4s poll tick) with a rock-solid pinned arrival time that only updates for meaningful events (delay, crowd report, reroute). Feed actual-vs-predicted data back to DB for ML improvement.

### Architecture

```
Trip started → Compute base travel minutes (walk + edges + platform wait)
     ↓
GPS within 100m of origin station? → Pin ETA (snapshot wall-clock arrival time)
     ↓
Display: (pinnedArrivalTime - now).inMinutes  ← steady countdown, never jitters
     ↓
Events that RE-PIN:
  • User submits delay report   → +N min to pinnedArrivalTime
  • User submits crowd report   → +extra wait min to pinnedArrivalTime
  • Reroute (off-route detected) → fresh Dijkstra from current stop → new pin
     ↓
Arrival → submit trip_feedback { predicted, actual, deviation, weather, ... }
     ↓
ML training aggregates feedback → updates eta_multiplier per route/slot
```

### Implementation

#### Phase 1 — Flutter core (pin + countdown)
- [x] Add `pinnedArrivalTime` / `pinnedRemainingMinutes` fields to `_TrackRouteScreenState`
- [x] Pin ETA when GPS shows user within 100m of origin station
- [x] Display counts down smoothly from pinned value
- [x] Only re-pin on: delay report, crowd report, reroute
- [x] Submit `trip_feedback` on arrival (actual vs predicted)

#### Phase 2 — Backend + DB
- [x] Create `trip_feedback` table in Supabase (see `supabase/migration_trip_feedback.sql`)
- [x] Add `POST /trip/feedback` endpoint to FastAPI backend
- [x] Wire ML aggregation script to consume `trip_feedback` and retrain `eta_multiplier`

#### Phase 3 — Weather integration
- [ ] Fetch Open-Meteo weather at trip start → attach to `trip_feedback`
- [ ] ML model learns rain/haze/heat multipliers per route

### Key rules
- ETA is **pinned once** and only changes for explicit events
- Normal station passing = no ETA change (countdown handles it naturally)
- Background crowd forecast refresh = never touches displayed ETA
- Crowd-sourced feedback loop: User A's actual arrival time improves User B's predicted ETA

## 10. Schedule-Ahead Trip Planner

**Goal:** User picks a destination + target arrival time → app tells them when to leave and which route to take.

### Flow
```
User selects "Plan ahead" → picks destination + target arrival time
     ↓
App fetches crowd forecasts for that future datetime
     ↓
Computes: walk to station + platform wait + train edges (with crowd multipliers)
     ↓
Works backwards from target arrival time:
   leaveBy = targetArrival - totalTripMinutes
     ↓
Displays: "Leave by 6:17 PM → Take KJ Line → Arrive by 7:00 PM"
```

### Implementation
- [x] Add "Plan ahead" button to the trip search screen
- [x] Add date/time picker for target arrival time
- [x] Use existing `fetchForecastGrid` with a future `DateTime` to get crowd predictions
- [x] Compute total minutes: walking (GPS→origin) + platform wait + sum of edge times (with crowd multipliers at future time)
- [x] Display "Leave by X → Arrive by Y" card with route timeline
- [ ] When user arrives at the departure time, auto-suggest starting the trip

## 11. Safety Check-In ("Are You Okay?")

**Goal:** During active tracking, if GPS shows <20m movement for 30+ consecutive minutes, prompt a check-in.

### Rules
| Condition | Action |
|---|---|
| GPS accuracy > 100m or stale (>2 min) | Skip check (don't mistake stale GPS for stillness) |
| Location service is OFF | Quiet skip — no prompt |
| Moved > 20m | Reset the 30-min timer |
| No movement for 30min AND trip still active | Show dialog: "You haven't moved in a while. Are you okay?" |
| User taps "I'm fine" | Dismiss, reset timer |
| User taps "Call emergency contact" | Open device dialer with emergency number |
| User taps "Cancel trip" | Stop tracking, clear trip |

- [x] Add stillness tracking: store last-moved position + timestamp, reset on movement > 20m
- [x] Show "Are you okay?" dialog on 30-min inactivity (only during active tracking)
- [ ] Implement emergency contact dialer integration
- [x] Add location-service-availability guard before prompting

## 12. Performance — 60fps

**Goal:** Smooth 60fps during tracking, no jank from full-tree rebuilds.

### Bottlenecks identified
| Issue | Impact | Fix |
|---|---|---|
| `AnimatedBuilder` wraps entire tracking UI | Rebuilds full tree 60fps on pulse animation | Split pulse into small widget with `RepaintBoundary` |
| `setState` every 4s in `_trackingTick` | Rebuilds entire screen (header + timeline + buttons) | Use `ValueListenableBuilder` for independent sections |
| Timeline list rebuilds from scratch each setState | List re-creates items even if data is same | Extract into separate widget with `const` constructors |
| `_TrackHeader` receives new objects each build | Can't be const-optimized | Pass raw values instead of computed objects |

- [ ] Wrap `AnimatedBuilder` in `RepaintBoundary` to isolate pulse repaints
- [ ] Replace `setState` in `_trackingTick` with targeted `ValueListenableBuilder` for header ETA + progress
- [ ] Make `_TrackHeader` accept raw ints/Strings instead of computed DateTime objects to enable const
- [ ] Add `const` constructors to `_TrackStopTile`, `_TrackHeader`, `_InfoBlock`

## 13. Stale synthetic data — migrate to real-data pipeline

**Current:** `generate_crowd_data.py` → `train_crowd_model.py` → `predict_and_upsert_crowd.py` (one-shot, never repeated)

**Target:** Daily retrain on real crowd_reports + trip_feedback

- [x] Create `aggregate_training_data.py` that queries Supabase for real report data
- [x] Create `run_daily_pipeline.py` that: aggregate → retrain → upsert
- [ ] Schedule daily cron: `python run_daily_pipeline.py` (via GitHub Actions or Windows Task Scheduler)
- [ ] Add weather history fetch to training pipeline (Open-Meteo)
- [ ] After pipeline is stable, deprecate synthetic data generation

## 14. Release

- [ ] Build APK: `flutter build apk --release`
- [ ] Build AppBundle: `flutter build appbundle --release`
- [ ] Verify app size (target < 40 MB for APK, < 30 MB for AAB)
- [ ] Tag release in git: `git tag v1.0.0`
- [ ] Create GitHub release with APK + changelog

## Legend

| Mark | Meaning |
|------|---------|
| [ ]  | Not started |
| [x]  | Done |

---

*Last updated: July 2026*
