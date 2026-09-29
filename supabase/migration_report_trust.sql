-- Community verification + weight-based blending + delay signals.
-- Tier 1 only: distinct-reporter voting, weighted median, no account friction.

ALTER TABLE public.crowd_reports
  ADD COLUMN IF NOT EXISTS verification_status TEXT NOT NULL DEFAULT 'pending',
  ADD COLUMN IF NOT EXISTS verification_reason TEXT,
  ADD COLUMN IF NOT EXISTS line_id TEXT,
  ADD COLUMN IF NOT EXISTS direction TEXT;

DO $$
BEGIN
  ALTER TABLE public.crowd_reports
    ADD CONSTRAINT crowd_reports_verification_status_check
    CHECK (verification_status IN ('pending', 'verified', 'flagged'));
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;

CREATE INDEX IF NOT EXISTS idx_crowd_reports_stop_recent
  ON public.crowd_reports (stop_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_crowd_reports_line_direction
  ON public.crowd_reports (line_id, direction, created_at DESC);

CREATE OR REPLACE FUNCTION public.verify_crowd_report()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_window INTERVAL := INTERVAL '30 minutes';
  v_support INT := 0;
  v_contradict INT := 0;
  v_required INT;
BEGIN
  IF NEW.user_id IS NULL THEN
    NEW.verification_status := 'pending';
    NEW.verification_reason := 'anonymous report';
    RETURN NEW;
  END IF;

  v_required := CASE WHEN NEW.source_type = 'delay' THEN 2 ELSE 1 END;

  SELECT COUNT(DISTINCT cr.user_id) INTO v_support
  FROM public.crowd_reports cr
  WHERE cr.stop_id = NEW.stop_id
    AND cr.id <> NEW.id
    AND cr.user_id IS NOT NULL
    AND cr.user_id <> NEW.user_id
    AND cr.source_type = NEW.source_type
    AND cr.created_at > now() - v_window
    AND (
      NEW.source_type = 'delay'
      OR (
        cr.occupancy_level BETWEEN 1 AND 5
        AND abs(cr.occupancy_level - NEW.occupancy_level) <= 1
      )
    );

  IF NEW.source_type <> 'delay' THEN
    SELECT COUNT(DISTINCT cr.user_id) INTO v_contradict
    FROM public.crowd_reports cr
    WHERE cr.stop_id = NEW.stop_id
      AND cr.id <> NEW.id
      AND cr.user_id IS NOT NULL
      AND cr.user_id <> NEW.user_id
      AND cr.source_type = NEW.source_type
      AND cr.created_at > now() - v_window
      AND cr.occupancy_level BETWEEN 1 AND 5
      AND abs(cr.occupancy_level - NEW.occupancy_level) >= 2;
  END IF;

  IF v_contradict >= 2 AND v_contradict > v_support THEN
    NEW.verification_status := 'flagged';
    NEW.verification_reason := 'contradicted by multiple recent reports';
  ELSIF v_support >= v_required THEN
    NEW.verification_status := 'verified';
    NEW.verification_reason := 'corroborated by distinct reporters';
    UPDATE public.crowd_reports
    SET verification_status = 'verified',
        verification_reason = 'corroborated by distinct reporters'
    WHERE stop_id = NEW.stop_id
      AND id <> NEW.id
      AND user_id IS NOT NULL
      AND user_id <> NEW.user_id
      AND source_type = NEW.source_type
      AND created_at > now() - v_window
      AND verification_status = 'pending'
      AND (
        NEW.source_type = 'delay'
        OR (
          occupancy_level BETWEEN 1 AND 5
          AND abs(occupancy_level - NEW.occupancy_level) <= 1
        )
      );
  ELSE
    NEW.verification_status := 'pending';
    NEW.verification_reason := 'awaiting corroboration';
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_verify_crowd_report ON public.crowd_reports;
CREATE TRIGGER trg_verify_crowd_report
  BEFORE INSERT ON public.crowd_reports
  FOR EACH ROW EXECUTE FUNCTION public.verify_crowd_report();

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
  v_median INT;
  v_total_weight NUMERIC;
  v_reports_count INT;
  v_blended INT;
BEGIN
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

  SELECT COUNT(*)::INT INTO v_reports_count
  FROM crowd_reports cr
  WHERE cr.stop_id = p_stop_id
    AND cr.source_type = 'user'
    AND cr.occupancy_level BETWEEN 1 AND 5
    AND cr.created_at > now() - INTERVAL '2 hours';

  WITH weighted AS (
    SELECT
      cr.occupancy_level,
      (CASE cr.verification_status
         WHEN 'verified' THEN 1.0
         WHEN 'flagged' THEN 0.0
         ELSE 0.5
       END)
      * GREATEST(
          0.2,
          1.0 - (EXTRACT(EPOCH FROM (now() - cr.created_at)) / 7200.0)
        ) AS weight
    FROM crowd_reports cr
    WHERE cr.stop_id = p_stop_id
      AND cr.source_type = 'user'
      AND cr.occupancy_level BETWEEN 1 AND 5
      AND cr.created_at > now() - INTERVAL '2 hours'
      AND cr.verification_status <> 'flagged'
  ),
  ordered AS (
    SELECT
      occupancy_level,
      SUM(weight) OVER (
        ORDER BY occupancy_level
        ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
      ) AS cum_weight,
      SUM(weight) OVER () AS total_weight
    FROM weighted
    WHERE weight > 0
  )
  SELECT occupancy_level, total_weight
  INTO v_median, v_total_weight
  FROM ordered
  WHERE cum_weight >= total_weight / 2.0
  ORDER BY occupancy_level
  LIMIT 1;

  IF v_total_weight IS NOT NULL AND v_total_weight >= 1.5 THEN
    v_blended := ROUND((v_forecast_level * 0.4) + (v_median * 0.6))::INT;
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
    CASE
      WHEN v_total_weight IS NOT NULL AND v_total_weight >= 1.5
        THEN 'forecast+user_blend'
      ELSE 'forecast'
    END,
    v_reports_count;
END;
$$;

CREATE OR REPLACE FUNCTION public.get_community_delay(
  p_line TEXT,
  p_direction TEXT DEFAULT NULL
) RETURNS TABLE (
  report_count INT,
  distinct_reporters INT,
  offset_minutes INT
)
LANGUAGE sql
STABLE
AS $$
  WITH recent AS (
    SELECT cr.user_id, COUNT(*) AS reports
    FROM public.crowd_reports cr
    WHERE cr.source_type = 'delay'
      AND cr.verification_status <> 'flagged'
      AND upper(trim(coalesce(cr.line_id, ''))) = upper(trim(coalesce(p_line, '')))
      AND upper(trim(coalesce(cr.direction, ''))) = upper(trim(coalesce(p_direction, '')))
      AND cr.user_id IS NOT NULL
      AND cr.created_at > now() - INTERVAL '20 minutes'
    GROUP BY cr.user_id
  )
  SELECT
    COALESCE(SUM(reports), 0)::INT,
    COUNT(*)::INT,
    CASE
      WHEN COUNT(*) >= 3 THEN LEAST(2 + (COUNT(*) - 3), 8)
      ELSE 0
    END
  FROM recent;
$$;

GRANT EXECUTE ON FUNCTION public.get_community_delay(TEXT, TEXT) TO anon, authenticated;
