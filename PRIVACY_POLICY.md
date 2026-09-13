# Privacy Policy — Smart Commuter Assistant+

**Last updated:** 13 September 2026

Smart Commuter Assistant+ ("the app") is a Klang Valley rail transit companion
that provides route planning, crowd forecasts, and journey tracking. This policy
explains what data the app collects, why, and how you can control or delete it.

## 1. Data we collect

| Data | Purpose | Required? |
|---|---|---|
| Email address & password | Account creation and authentication (via Supabase Auth) | Only if you create an account (guest mode is optional) |
| Display name / handle / bio / avatar | Your public profile shown to friends and party members | Optional |
| Precise location (GPS) | Nearest-station detection, arrival lookup, and the 500 m station geofence | Only while the app is in use and you grant permission |
| Coarse station location | Party/race member positions are shared only as a **nearest station**, never raw coordinates | Only during an active party/race |
| Crowd & delay reports | Community crowd levels; stored with your user id (location is rounded to ~1 km) | Optional |
| Trip history & feedback | ETA learning; route-planning improvements | Optional |
| Device/usage analytics | Crash reporting (Sentry) | Optional |

Location is **foreground-only**. The app does not track you in the background.

## 2. How data is used

- To authenticate you and let you use social features (friends, parties, races).
- To compute routes, arrivals, and crowd forecasts.
- To improve the routing agent using anonymised predicted-vs-actual trip feedback.
- To show other party members which station you are near (coarse station only).

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
- Party/race location data is ephemeral — it is deleted when a party closes or a member leaves.

## 5. Your rights & account deletion

You can delete your account at any time from **Profile → Delete Account** in the app.
Deleting your account permanently removes your profile, friendships, and trip history.

If you are unable to open the app, you may request deletion at:
**https://<your-deletion-url>.com** (or email us at **support@example.com**).

## 6. Children's privacy

This app is not directed at children under 13. We do not knowingly collect data
from children under 13.

## 7. Contact

Questions about this policy: **support@example.com**

> **Disclaimer:** Smart Commuter Assistant+ is an independent, unofficial app and
> is not affiliated with, endorsed by, or sponsored by Rapid KL or Prasarana Malaysia.
> Transit data is provided for reference under the data.gov.my open data terms, with
> attribution to Prasarana Malaysia.
