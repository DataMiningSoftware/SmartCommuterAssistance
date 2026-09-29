# Play Store Listing — Smart Commuter Assistant+

## Store listing

**App name:** Smart Commuter Assistant+

**Short description (80 chars max):**
Klang Valley rail routes, arrivals and crowd forecasts — no account needed.

**Full description:**

Plan your Klang Valley commute without the guesswork.

Smart Commuter Assistant+ covers the whole rail network — LRT Kelana Jaya,
Ampang and Sri Petaling, MRT Kajang and Putrajaya, KL Monorail, BRT Sunway,
KTM Komuter, and the KLIA Ekspres and KLIA Transit airport lines.

ROUTE PLANNING
• Station-to-station routes across every line, with interchange handling
• Fastest, balanced and comfort profiles
• Estimated fares for Rapid KL, KTM and ERL journeys

CROWD FORECASTS
• Hourly 1–5 crowd levels for every station, trained on real rider reports
• Live rider reports blended into the forecast
• Nearby-station crowd board using your location

ARRIVALS & TRACKING
• Scheduled arrivals from official GTFS timetables (Prasarana and KTMB)
• Pinned ETA that counts down steadily — no jitter, no gaslighting
• Report delays and crowds with one tap; the community benefits instantly

PRIVACY FIRST
• No account or email required — the app starts anonymously
• Location is foreground-only and rounded to ~1 km when sent to servers
• Optional "improve predictions" consent for model training, off by default
• Delete all your data anytime from Profile

Transit data from data.gov.my / Prasarana Malaysia / KTMB.
Independent, unofficial app — not affiliated with Rapid KL or Prasarana.

## Categorisation

- **Category:** Maps & Navigation
- **Tags:** transit, public transport, trains, commute
- **Contains ads:** No
- **In-app purchases:** No

## Data safety form (answers)

| Question | Answer |
|---|---|
| Does your app collect or share any required user data? | Yes (location, optional reports) |
| Is all collected data encrypted in transit? | Yes |
| Do you provide a way for users to request data deletion? | Yes — Profile → Delete my data |
| Location — approximate/precise | Collected (optional, foreground only), not shared with third parties |
| Personal info — email | Only if the user creates an optional account; not required |
| App activity — in-app actions | Crowd/delay reports and trip feedback; used for app functionality |
| Device or other IDs | Anonymous device identifier for rate limits and consent |
| Data sold to third parties? | No |

## Content rating questionnaire

- Violence, sexuality, language, controlled substances: **No** to all
- User-generated content sharing: **crowd/delay reports** (moderated, anonymised)
- Location sharing with other users: **No**

## Store assets checklist

- [x] App icon (512×512) — `docs/release/play-icon-512.png`
- [x] Feature graphic 1024×500 — `docs/release/feature-graphic-1024x500.png`
- [x] Phone screenshots (1080×1920) — `docs/release/screenshots/` (3 of 8; add geographic map, track and profile shots when convenient)
- [x] Privacy policy URL: https://dataminingsoftware.github.io/SmartCommuterAssistance/privacy.html
- [x] Release notes for v1.0.0 — see below

## Release notes — v1.0.0

- Route planning across LRT, MRT, Monorail, BRT, KTM Komuter and KLIA Ekspres/Transit
- Hourly crowd forecasts for every station, blended with live rider reports
- Scheduled arrivals from official GTFS feeds
- Estimated fares for Rapid KL, KTM and ERL journeys
- Pinned ETA countdown, nearby stations, favorites and offline mode
- No account needed — anonymous by default with optional data consent

## Release build

- Signed AAB is produced by CI (`Android Build` job) and attached as the
  `android-release` artifact on every push to `main`.
- Package name: `com.nawfal.smartcommuter`
- Version: `1.0.0+1` (`app/pubspec.yaml`)
