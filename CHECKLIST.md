# Smart Commuter Assistant+ — Feature Checklist

<!--
  How to keep this file up to date:
  1. When you complete a feature, change [ ] to [x]
  2. When you add a new feature, add a new row above the "Uncategorized" section
  3. Commit and push after every meaningful change

  For automated tracking, you can also mirror this in GitHub Issues:
  - Create one issue per item below
  - Tag with labels like `status:done`, `status:wip`, `status:todo`
  - Close issues as you complete them
-->

## Data & Forecasting Accuracy

- [ ] ❌ Drop synthetic ML training — stop relying on simulated data labels
- [x] ✅ Import official GTFS static feed (Malaysia Open API rapid-rail-kl)
- [x] ✅ Refresh GTFS data daily (24h cache in `gtfs_service.py`)
- [x] ⚠️ Build crowd predictions from real user reports + historical patterns (blend SQL function works; ML baseline still synthetic)
- [ ] ❌ Incorporate external features (weather, events)
- [ ] ❌ Time-based data splits for model evaluation

## Architecture & Backend

- [x] ⚠️ Centralize heavy logic in FastAPI (route planning, GTFS arrivals, crowd validation done; SQL blending in-database)
- [ ] ❌ `GET /stations` endpoint
- [ ] ❌ `GET /journey` endpoint
- [x] ✅ `GET /arrivals/station/{id}` endpoint
- [x] ✅ `GET /arrivals/nearest` endpoint
- [x] ✅ `POST /crowd/report` endpoint (geo-fenced, rate-limited, consensus)
- [x] ✅ `GET /crowd/blend` endpoint
- [x] ✅ `POST /plan-trip` endpoint (Dijkstra, 3 profiles)
- [ ] ❌ Production deployment of FastAPI backend to Render

## UI & User Experience

- [x] ✅ Scheduled arrivals service (built in `TrainArrivalService` + `gtfs_service.py`; **unavailable until backend deployed**)
- [x] ⚠️ Nearest-station card with arrival info (crowd lookup works; arrivals need backend)
- [x] ✅ Schematic transit map (InteractiveViewer, tappable stations, route highlighting)
- [x] ✅ Grey out non-selected lines on schematic map
- [x] ✅ Label data sources transparently ("Rider report", "Hourly forecast", "Forecast + rider reports")
- [x] ✅ Remove Flutter debug banner
- [x] ✅ Add WIP badge (hammer icon + "W.I.P")

## Security & Operations

- [x] ✅ RLS policies hardened (authenticated role required for inserts)
- [x] ✅ Privacy-safe location handling (consent dialog + coordinate redaction)
- [x] ✅ Sentry crash/error logging
- [x] ✅ CI checks for Flutter analyze/test
- [x] ✅ CI checks for Python lint/tests

## Anti-Reset & Anti-Fraud Crowd System

- [x] ✅ Time-series storage (append-only `crowd_reports`; `historical_crowds` snapshots)
- [x] ✅ Time-decay blending (40% ML + 60% age-weighted user reports + 14-day history fallback)
- [x] ✅ Daily snapshot into `historical_crowds`
- [x] ✅ Geo-fencing (server-side + client-side, 500m threshold)
- [x] ✅ Rate limiting (1 report per station per 2 hours per user)
- [x] ✅ Consensus mechanism (extreme reports need corroboration within 30 min)

## Transit Map

- [x] ✅ Percentage-based station coordinate JSON (24 stations)
- [x] ✅ InteractiveViewer for zoom/pan
- [x] ✅ Tappable station circles with hover + origin/destination markers
- [x] ✅ Route line highlighting via CustomPainter
- [x] ✅ Bottom sheet actions (View Details, Set Origin, Set Destination)
- [x] ✅ Plan Route card when both origin and destination are selected

## Legend

| Icon | Meaning |
|------|---------|
| ✅ | Done |
| ⚠️ | Partially done |
| ❌ | Not done |

---

*Last updated: July 2026*
