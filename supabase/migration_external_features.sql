-- External demand/weather/holiday features used by the crowd model pipeline.
-- Written nightly by scripts/fetch_external_features.py (service key),
-- readable by the app and the training jobs.

CREATE TABLE IF NOT EXISTS public.external_daily_features (
  date            DATE NOT NULL,
  line_id         TEXT NOT NULL,
  ridership       INTEGER,
  ridership_ratio NUMERIC(6,4) DEFAULT 1.0,
  rain_mm         NUMERIC(6,2) DEFAULT 0.0,
  is_holiday      BOOLEAN NOT NULL DEFAULT FALSE,
  event_flag      BOOLEAN NOT NULL DEFAULT FALSE,
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (date, line_id)
);

CREATE INDEX IF NOT EXISTS idx_external_features_line_date
  ON public.external_daily_features (line_id, date DESC);

ALTER TABLE public.external_daily_features ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Anyone can read external_daily_features" ON public.external_daily_features;
CREATE POLICY "Anyone can read external_daily_features"
  ON public.external_daily_features
  FOR SELECT
  TO anon, authenticated
  USING (true);
