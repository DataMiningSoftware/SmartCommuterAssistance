-- ERL flight volume feature (KLIA arrivals/departures per day).

ALTER TABLE public.external_daily_features
  ADD COLUMN IF NOT EXISTS flight_count INTEGER NOT NULL DEFAULT 0;
