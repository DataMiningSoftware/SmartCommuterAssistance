# Privacy Policy — Smart Commuter Assistant+

**Last updated:** 30 September 2026

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
- Crowd reports are retained in unlinked, anonymised form to power community crowd forecasting (location rounded to ~1 km).
- Trip feedback is retained only while you have granted model-training consent;
  withdrawing consent excludes your data from all future training runs.

## 5. Your rights & account deletion

You can delete your data at any time from **Profile → Delete my data** (or
**Delete Account** if you created one) in the app. This removes your anonymous
device profile, your account and login credentials, and your trip feedback.
Your contributed crowd and delay reports are unlinked from your identity and
retained in anonymised form so community crowd forecasts stay accurate for
other riders.

You can withdraw model-training consent at any time in **Profile → Improve
predictions with my trip data**; your data is then excluded from all future
training runs.

If you are unable to open the app, you may request deletion at
**https://dataminingsoftware.github.io/SmartCommuterAssistance/delete-account.html**
or by emailing **mnawfalbn@gmail.com**. We process deletion requests within
30 days.

## 6. Children's privacy

This app is not directed at children under 13. We do not knowingly collect data
from children under 13.

## 7. Contact

Questions about this policy: **mnawfalbn@gmail.com**

You can also reach us via the issue tracker:
**https://github.com/DataMiningSoftware/SmartCommuterAssistance/issues**

> **Disclaimer:** Smart Commuter Assistant+ is an independent, unofficial app and
> is not affiliated with, endorsed by, or sponsored by Rapid KL or Prasarana Malaysia.
> Transit data is provided for reference under the data.gov.my open data terms, with
> attribution to Prasarana Malaysia.
