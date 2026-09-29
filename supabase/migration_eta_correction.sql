-- Consent-aware ETA correction aggregate.
-- Replaces the app's raw trip_feedback read: only consented users contribute,
-- raw rows stay private (own-row RLS), and the result is bounded.

CREATE OR REPLACE FUNCTION public.get_eta_correction(
  p_route_id TEXT,
  p_is_weekend BOOLEAN,
  p_hour INT DEFAULT NULL
) RETURNS NUMERIC
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT CASE
    WHEN COUNT(*) < 5 THEN 0
    ELSE GREATEST(-15, LEAST(15, ROUND(AVG(tf.deviation_min))))
  END
  FROM public.trip_feedback tf
  JOIN public.profiles p ON p.id = tf.user_id
  WHERE p.ml_training_consent = TRUE
    AND tf.user_id IS NOT NULL
    AND tf.route_id = upper(trim(p_route_id))
    AND tf.is_weekend = p_is_weekend
    AND (p_hour IS NULL OR tf.time_of_day = p_hour);
$$;

GRANT EXECUTE ON FUNCTION public.get_eta_correction(TEXT, BOOLEAN, INT)
  TO anon, authenticated;
