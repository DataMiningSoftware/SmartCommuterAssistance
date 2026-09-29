-- KTMB GTFS-Realtime derived service health per line/direction.
-- Written every few minutes by scripts/fetch_service_health.py.

CREATE TABLE IF NOT EXISTS public.service_health (
  line_id         TEXT NOT NULL,
  direction       TEXT NOT NULL DEFAULT '',
  avg_delay_min   NUMERIC(5,1) NOT NULL DEFAULT 0,
  vehicle_count   INTEGER NOT NULL DEFAULT 0,
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (line_id, direction)
);

ALTER TABLE public.service_health ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Anyone can read service_health" ON public.service_health;
CREATE POLICY "Anyone can read service_health"
  ON public.service_health
  FOR SELECT
  TO anon, authenticated
  USING (true);
