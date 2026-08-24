-- Migration: add day_of_week to crowd_forecast_hourly
-- Replaces binary is_weekend with 0-6 day_of_week for granular weekday forecasts.

-- 1. Add the column (nullable initially to backfill existing rows).
alter table public.crowd_forecast_hourly
  add column if not exists day_of_week smallint
  check (day_of_week between 0 and 6);

-- 2. Backfill existing rows: is_weekend=true → day_of_week=6 (Saturday),
--    is_weekend=false → day_of_week=0 (Monday, best guess for legacy data).
update public.crowd_forecast_hourly
  set day_of_week = case when is_weekend = true then 6 else 0 end
  where day_of_week is null;

-- 3. Make it not null now that all rows have a value.
alter table public.crowd_forecast_hourly
  alter column day_of_week set not null;

-- 4. Drop the old unique constraint and replace with day_of_week variant.
alter table public.crowd_forecast_hourly
  drop constraint if exists crowd_forecast_hourly_stop_id_forecast_hour_is_weekend_key;

alter table public.crowd_forecast_hourly
  add constraint crowd_forecast_hourly_stop_hour_dow_key
  unique (stop_id, forecast_hour, day_of_week);

-- 5. Drop the old index and create a new one on the new column.
drop index if exists idx_crowd_forecast_stop_hour_weekend;

create index if not exists idx_crowd_forecast_stop_hour_dow
  on public.crowd_forecast_hourly (stop_id, forecast_hour, day_of_week);

-- 6. Keep is_weekend for backward compat; it is now derived.

-- 7. Recreate get_blended_crowd_level to be day-of-week aware.
--    The forecast table now has per-day rows (day_of_week 0-6, Python
--    convention Monday=0). Filtering only on is_weekend would match both
--    Saturday and Sunday rows arbitrarily.
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
  v_dow INT := (EXTRACT(DOW FROM now())::INT + 6) % 7;
  v_forecast_level INT;
  v_reports_avg NUMERIC;
  v_reports_count INT;
  v_blended INT;
BEGIN
  -- ML forecast baseline, preferring the exact day of week.
  SELECT cf.occupancy_level INTO v_forecast_level
  FROM crowd_forecast_hourly cf
  WHERE cf.stop_id = p_stop_id
    AND cf.forecast_hour = v_hour
    AND cf.day_of_week = v_dow
  LIMIT 1;

  IF v_forecast_level IS NULL THEN
    SELECT cf.occupancy_level INTO v_forecast_level
    FROM crowd_forecast_hourly cf
    WHERE cf.stop_id = p_stop_id
      AND cf.forecast_hour = v_hour
      AND cf.is_weekend = v_is_weekend
    LIMIT 1;
  END IF;

  IF v_forecast_level IS NULL THEN
    v_forecast_level := 2;
  END IF;

  SELECT
    COUNT(*)::INT,
    AVG(cr.occupancy_level)::NUMERIC
  INTO v_reports_count, v_reports_avg
  FROM crowd_reports cr
  WHERE cr.stop_id = p_stop_id
    AND cr.source_type = 'user'
    AND cr.occupancy_level BETWEEN 1 AND 5
    AND cr.created_at > now() - INTERVAL '2 hours';

  IF v_reports_count > 0 AND v_reports_avg IS NOT NULL THEN
    v_blended := ROUND((v_forecast_level * 0.4) + (v_reports_avg * 0.6))::INT;
  ELSE
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
