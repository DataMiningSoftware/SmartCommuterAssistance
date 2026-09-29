# Privacy Policy — Smart Commuter Assistant+

**Last updated:** 29 September 2026

Smart Commuter Assistant+ ("the app") is a Klang Valley rail transit companion
that provides route planning, crowd forecasts, and journey tracking. This policy
explains what data the app collects, why, and how you can control or delete it.

## 1. Data we collect

| Data | Purpose | Required? |
|---|---|---|
| Anonymous device identifier | Pseudonymous identity for rate limits, community consensus checks and — with your consent — model training. No name or email is collected. | Automatic |
| Email address & password | Optional account sync, if you choose to create an account later | Only if you create an account (not required) |
| Display name / handle / bio / avatar | Your public profile shown to friends and party members | Optional |
| Precise location (GPS) | Nearest-station detection, arrival lookup, and the 500 m station geofence | Only while the app is in use and you grant permission |
| Coarse station location | Party/race member positions are shared only as a **nearest station**, never raw coordinates | Only during an active party/race |
| Crowd & delay reports | Community crowd levels; stored with your user id (location is rounded to ~1 km) | Optional |
| Trip history & feedback | ETA learning; route-planning improvements | Optional |
| Device/usage analytics | Crash reporting (Sentry) | Optional |

Location is **foreground-only**. The app does not track you in the background.

## 2. How data is used

- To authenticate you and let you use the app.
- To compute routes, arrivals, crowd forecasts and fares.
- To show you nearby stations and live crowd levels.
- **Model training (optional, off by default):** with your explicit consent, we
  use your crowd and delay reports and your predicted-vs-actual trip times to
  train our crowd-prediction and ETA models. This improves crowd forecasts,
  wait-time estimates and schedule planning for all riders. Only anonymised,
  aggregated data is used; we never sell your data. You can grant or withdraw
  this consent at any time in **Profile → Improve predictions with my trip data**.

We do **not** sell your data.

## 3. Third-party services

- **Supabase** (Postgres database + authentication) — stores your account and app data.
- **Render** (backend hosting) — serves the routing/arrivals API.
- **Sentry** — crash and error reporting.
- **data.gov.my / Prasarana** — official GTFS schedule data.
- **OpenStreetMap / CARTO** — map tiles.
- **Open-Meteo** — weather data.

## 4. Data retention

- Account data is retained until you delete your account.
- Crowd reports are retained to power crowd forecasting (location rounded to ~1 km).
- Trip feedback is retained only while you have granted model-training consent;
  withdrawing consent excludes your data from all future training runs.

## 5. Your rights & account deletion

You can delete your data at any time from **Profile → Delete my data** in the app.
This permanently removes your anonymous device profile, contributed reports and
trip feedback. There is no account to delete unless you voluntarily created one.

You can withdraw model-training consent at any time in **Profile → Improve
predictions with my trip data**; your data is then excluded from all future
training runs.

If you are unable to open the app, you may request deletion at:
**https://github.com/DataMiningSoftware/SmartCommuterAssistance/issues**.

## 6. Children's privacy

This app is not directed at children under 13. We do not knowingly collect data
from children under 13.

## 7. Contact

Questions about this policy: **https://github.com/DataMiningSoftware/SmartCommuterAssistance/issues**

> **Disclaimer:** Smart Commuter Assistant+ is an independent, unofficial app and
> is not affiliated with, endorsed by, or sponsored by Rapid KL or Prasarana Malaysia.
> Transit data is provided for reference under the data.gov.my open data terms, with
> attribution to Prasarana Malaysia.
