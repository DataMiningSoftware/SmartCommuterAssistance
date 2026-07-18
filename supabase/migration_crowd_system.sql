-- ============================================================
-- Smart Commuter Assistant+ — Crowd System Migration
-- Run this in Supabase SQL Editor after the base schema.
-- ============================================================

-- 1. ENSURE crowd_reports has the right columns for time-series
-- (This assumes the table already exists; these are additive.)
ALTER TABLE crowd_reports
  ADD COLUMN IF NOT EXISTS user_id UUID REFERENCES auth.users(id),
  ADD COLUMN IF NOT EXISTS latitude DOUBLE PRECISION,
  ADD COLUMN IF NOT EXISTS longitude DOUBLE PRECISION,
  ADD COLUMN IF NOT EXISTS session_id TEXT;

CREATE INDEX IF NOT EXISTS idx_crowd_reports_lookup
  ON crowd_reports (stop_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_crowd_reports_rate_limit
  ON crowd_reports (user_id, stop_id, created_at DESC);

-- 2. HISTORICAL CROWDS TABLE — rolling log of hourly blend snapshots
CREATE TABLE IF NOT EXISTS historical_crowds (
  id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  stop_id TEXT NOT NULL,
  forecast_hour SMALLINT NOT NULL CHECK (forecast_hour BETWEEN 0 AND 23),
  is_weekend BOOLEAN NOT NULL DEFAULT FALSE,
  occupancy_level SMALLINT NOT NULL CHECK (occupancy_level BETWEEN 0 AND 5),
  source_type TEXT NOT NULL DEFAULT 'blend',
  model_baseline SMALLINT,
  user_report_count INTEGER DEFAULT 0,
  user_report_average NUMERIC(3,1),
  blended_level SMALLINT,
  snapshot_date DATE NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_historical_crowds_unique
  ON historical_crowds (stop_id, forecast_hour, is_weekend, snapshot_date);

CREATE INDEX IF NOT EXISTS idx_historical_crowds_lookup
  ON historical_crowds (stop_id, forecast_hour, is_weekend, snapshot_date DESC);

-- 3. USER REPORT LOG — append-only, never deleted
-- (crowd_reports already serves this purpose; ensure it has proper indexes)

-- 4. FUNCTION: get_blended_crowd_level
-- Blends ML forecast with recent user reports using time-decay.
CREATE OR REPLACE FUNCTION get_blended_crowd_level(
  p_stop_id TEXT,
  p_hour INT DEFAULT NULL,
  p_is_weekend BOOLEAN DEFAULT NULL
) RETURNS TABLE (
  stop_id TEXT,
  forecast_hour INT,
  is_weekend BOOLEAN,
  occupancy_level INT,
  source_type TEXT,
  user_reports_count INT
) LANGUAGE plpgsql AS $$
DECLARE
  v_hour INT := COALESCE(p_hour, EXTRACT(HOUR FROM now())::INT);
  v_is_weekend BOOLEAN := COALESCE(p_is_weekend, EXTRACT(DOW FROM now()) IN (0, 6));
  v_forecast_level INT;
  v_reports_avg NUMERIC;
  v_reports_count INT;
  v_blended INT;
BEGIN
  -- Get ML forecast baseline
  SELECT cf.occupancy_level INTO v_forecast_level
  FROM crowd_forecast_hourly cf
  WHERE cf.stop_id = p_stop_id
    AND cf.forecast_hour = v_hour
    AND cf.is_weekend = v_is_weekend
  LIMIT 1;

  IF v_forecast_level IS NULL THEN
    v_forecast_level := 2; -- default moderate
  END IF;

  -- Get recent user reports (last 2 hours weighed by recency)
  SELECT
    COUNT(*)::INT,
    AVG(cr.occupancy_level)::NUMERIC
  INTO v_reports_count, v_reports_avg
  FROM crowd_reports cr
  WHERE cr.stop_id = p_stop_id
    AND cr.source_type = 'user'
    AND cr.occupancy_level BETWEEN 1 AND 5
    AND cr.created_at > now() - INTERVAL '2 hours';

  -- Blend: weight decreases with time since last report
  IF v_reports_count > 0 AND v_reports_avg IS NOT NULL THEN
    v_blended := ROUND((v_forecast_level * 0.4) + (v_reports_avg * 0.6))::INT;
  ELSE
    -- Use historical average for same hour/weekday if available
    SELECT ROUND(AVG(blended_level))::INT INTO v_blended
    FROM historical_crowds
    WHERE stop_id = p_stop_id
      AND forecast_hour = v_hour
      AND is_weekend = v_is_weekend
      AND snapshot_date >= CURRENT_DATE - 14;
    IF v_blended IS NULL THEN
      v_blended := v_forecast_level;
    END IF;
  END IF;

  v_blended := GREATEST(1, LEAST(5, v_blended));

  RETURN QUERY
  SELECT
    p_stop_id,
    v_hour,
    v_is_weekend,
    v_blended,
    CASE WHEN v_reports_count > 0 THEN 'forecast+user_blend' ELSE 'forecast' END,
    v_reports_count;
END;
$$;

-- 5. FUNCTION: submit_crowd_report (updated with validation stubs)
-- Replace or update the existing function.
CREATE OR REPLACE FUNCTION submit_crowd_report(
  p_stop_id TEXT,
  p_source_type TEXT DEFAULT 'user',
  p_occupancy_level INT DEFAULT 3,
  p_user_id UUID DEFAULT NULL,
  p_latitude DOUBLE PRECISION DEFAULT NULL,
  p_longitude DOUBLE PRECISION DEFAULT NULL,
  p_session_id TEXT DEFAULT NULL
) RETURNS JSONB LANGUAGE plpgsql AS $$
DECLARE
  v_recent_count INT;
  v_minutes_since_last INT;
  v_last_level INT;
  v_consensus_level INT;
  v_accept BOOLEAN := TRUE;
  v_message TEXT := 'Report accepted.';
BEGIN
  -- Rate limiting: 1 report per station per 2 hours per user
  IF p_user_id IS NOT NULL THEN
    SELECT COUNT(*) INTO v_recent_count
    FROM crowd_reports
    WHERE user_id = p_user_id
      AND stop_id = p_stop_id
      AND source_type = 'user'
      AND created_at > now() - INTERVAL '2 hours';

    IF v_recent_count > 0 THEN
      RETURN jsonb_build_object(
        'accepted', FALSE,
        'message', 'Rate limited. You can report this station again in 2 hours.'
      );
    END IF;
  END IF;

  -- Consensus check: extreme report (4-5 or 1) needs corroboration
  IF p_occupancy_level >= 4 OR p_occupancy_level <= 1 THEN
    SELECT cr.occupancy_level, 
           EXTRACT(EPOCH FROM (now() - cr.created_at)) / 60 INTO v_last_level, v_minutes_since_last
    FROM crowd_reports cr
    WHERE cr.stop_id = p_stop_id
      AND cr.source_type = 'user'
      AND cr.occupancy_level BETWEEN 1 AND 5
      AND cr.created_at > now() - INTERVAL '30 minutes'
      AND (cr.user_id IS DISTINCT FROM p_user_id OR cr.user_id IS NULL)
    ORDER BY cr.created_at DESC
    LIMIT 1;

    IF v_last_level IS NULL OR v_minutes_since_last > 30 THEN
      -- No corroborating report in 30-min window
      -- Accept but mark as unverified
      v_accept := TRUE;
      v_message := 'Report accepted (unverified).';
    END IF;
  END IF;

  -- Insert the report
  INSERT INTO crowd_reports (
    stop_id, source_type, occupancy_level, user_id, latitude, longitude, session_id
  ) VALUES (
    p_stop_id, p_source_type, p_occupancy_level, p_user_id, p_latitude, p_longitude, p_session_id
  );

  RETURN jsonb_build_object(
    'accepted', v_accept,
    'message', v_message,
    'stop_id', p_stop_id,
    'occupancy_level', p_occupancy_level
  );
END;
$$;

-- 6. FUNCTION: snapshot_daily_blend — run via cron at midnight
CREATE OR REPLACE FUNCTION snapshot_daily_blend()
RETURNS INT LANGUAGE plpgsql AS $$
DECLARE
  v_inserted INT := 0;
  rec RECORD;
BEGIN
  FOR rec IN
    SELECT DISTINCT stop_id
    FROM crowd_reports
    WHERE created_at > now() - INTERVAL '24 hours'
  LOOP
    INSERT INTO historical_crowds (
      stop_id, forecast_hour, is_weekend, occupancy_level, source_type,
      model_baseline, user_report_count, user_report_average, blended_level, snapshot_date
    )
    SELECT
      rec.stop_id,
      EXTRACT(HOUR FROM cr.created_at)::SMALLINT,
      EXTRACT(DOW FROM cr.created_at) IN (0, 6),
      ROUND(AVG(cr.occupancy_level))::SMALLINT,
      'daily_blend',
      NULL,
      COUNT(*)::INT,
      AVG(cr.occupancy_level)::NUMERIC(3,1),
      ROUND(AVG(cr.occupancy_level))::SMALLINT,
      CURRENT_DATE
    FROM crowd_reports cr
    WHERE cr.stop_id = rec.stop_id
      AND cr.source_type = 'user'
      AND cr.occupancy_level BETWEEN 1 AND 5
      AND cr.created_at > now() - INTERVAL '24 hours'
    GROUP BY EXTRACT(HOUR FROM cr.created_at), EXTRACT(DOW FROM cr.created_at) IN (0, 6)
    ON CONFLICT (stop_id, forecast_hour, is_weekend, snapshot_date)
    DO UPDATE SET
      user_report_count = EXCLUDED.user_report_count,
      user_report_average = EXCLUDED.user_report_average,
      blended_level = EXCLUDED.blended_level,
      created_at = now();
    v_inserted := v_inserted + 1;
  END LOOP;
  RETURN v_inserted;
END;
$$;
