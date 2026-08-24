# Smart Commuter Assistant+

A Flutter app for navigating Malaysia's Klang Valley rail network with live crowd levels, ETAs, and route planning.

## Architecture

| Component | Tech | Location |
|---|---|---|
| Mobile app | Flutter | `app/` |
| Backend API | FastAPI | `backend/` |
| Database | Supabase (Postgres) | `supabase/` (migrations) |
| ML pipeline | Python (scikit-learn) | `scripts/` |
| CI/CD | GitHub Actions | `.github/workflows/` |

## Directory structure

```
.
├── app/                 # Flutter app (lib/, assets/, android/)
├── backend/             # FastAPI backend (main.py, Dockerfile)
├── scripts/             # ML training, data gen, SQL, coordinate tools
├── supabase/            # DB migrations + RLS policies
├── tests/               # Python tests
├── docker/              # ML worker container
├── .github/workflows/   # CI, cron (forecasts), deploy
├── Dockerfile           # Backend image (used by Cloud Run)
├── docker-compose.yml   # Local ML worker
├── Makefile             # Dev targets
└── opencode.json        # opencode agent config
```

## Local development

**Flutter app**
```bash
cd app
flutter pub get
flutter run --dart-define-from-file=env/dev.json
```

**Backend**
```bash
cd backend
python -m uvicorn main:app --reload
# or: .\run_backend.ps1
```

**Tests**
```bash
pytest tests/            # Python
cd app && flutter test   # Flutter
```

## Environment variables

Copy `.env.example` → set `SUPABASE_URL`, `SUPABASE_SERVICE_KEY`. The Flutter app reads `app/env/dev.json` (`dev.template.json` is the template).

## Deployment

- **App** → `flutter build appbundle --release` → upload to Google Play Console.
- **Backend** → Google Cloud Run (free tier): `gcloud run deploy smart-commuter-backend --source=. --region=asia-southeast1 --port=8000 --allow-unauthenticated`.
- **Cron/ML** → GitHub Actions (`crowd-forecast.yml`, `snapshot-daily-blend.yml`) write to Supabase.

See `CHECKLIST.md` for the full release/roadmap status.
