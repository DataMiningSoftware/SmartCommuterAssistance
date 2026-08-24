-- ============================================================
-- Smart Commuter Assistant+ — Trip Feedback Migration
-- Stores actual-vs-predicted ETA per trip for ML retraining.
-- ============================================================

CREATE TABLE IF NOT EXISTS trip_feedback (
  id              BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  route_id        TEXT NOT NULL,
  origin_stop     TEXT NOT NULL,
  dest_stop       TEXT NOT NULL,
  predicted_min   INTEGER NOT NULL,
  actual_min      INTEGER NOT NULL,
  deviation_min   INTEGER NOT NULL,
  crowd_at_start  SMALLINT,
  delays_reported INTEGER DEFAULT 0,
  crowds_reported INTEGER DEFAULT 0,
  walk_distance_m DOUBLE PRECISION,
  weather         TEXT,
  time_of_day     SMALLINT,
  day_of_week     SMALLINT,
  is_weekend      BOOLEAN,
  created_at      TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_trip_feedback_route_lookup
  ON trip_feedback (route_id, time_of_day, day_of_week);

CREATE INDEX IF NOT EXISTS idx_trip_feedback_deviation
  ON trip_feedback (route_id, deviation_min);

ALTER TABLE trip_feedback ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "anon can insert trip feedback" ON trip_feedback;
CREATE POLICY "anon can insert trip feedback"
  ON trip_feedback
  FOR INSERT
  TO anon, authenticated
  WITH CHECK (true);

DROP POLICY IF EXISTS "anon can read trip feedback" ON trip_feedback;
CREATE POLICY "anon can read trip feedback"
  ON trip_feedback
  FOR SELECT
  TO anon, authenticated
  USING (true);
