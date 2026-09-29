-- ============================================================
-- Smart Commuter Assistant+ — ML Training Consent
-- Per-user opt-in for using contributed data to train models.
-- ============================================================

ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS ml_training_consent BOOLEAN NOT NULL DEFAULT FALSE,
  ADD COLUMN IF NOT EXISTS consent_policy_version TEXT,
  ADD COLUMN IF NOT EXISTS consent_updated_at TIMESTAMPTZ;

CREATE TABLE IF NOT EXISTS public.consent_events (
  id              BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  user_id         UUID REFERENCES auth.users(id) ON DELETE CASCADE,
  granted         BOOLEAN NOT NULL,
  policy_version  TEXT,
  source          TEXT,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_consent_events_user
  ON public.consent_events (user_id, created_at DESC);

ALTER TABLE public.consent_events ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users insert own consent events" ON public.consent_events;
CREATE POLICY "Users insert own consent events"
  ON public.consent_events
  FOR INSERT
  TO authenticated
  WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users read own consent events" ON public.consent_events;
CREATE POLICY "Users read own consent events"
  ON public.consent_events
  FOR SELECT
  TO authenticated
  USING (auth.uid() = user_id);

ALTER TABLE public.trip_feedback
  ADD COLUMN IF NOT EXISTS user_id UUID REFERENCES auth.users(id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS idx_trip_feedback_user
  ON public.trip_feedback (user_id);

DROP POLICY IF EXISTS "anon can insert trip feedback" ON public.trip_feedback;
DROP POLICY IF EXISTS "anon can read trip feedback" ON public.trip_feedback;

DROP POLICY IF EXISTS "Users insert own trip feedback" ON public.trip_feedback;
CREATE POLICY "Users insert own trip feedback"
  ON public.trip_feedback
  FOR INSERT
  TO authenticated
  WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users read own trip feedback" ON public.trip_feedback;
CREATE POLICY "Users read own trip feedback"
  ON public.trip_feedback
  FOR SELECT
  TO authenticated
  USING (auth.uid() = user_id);

CREATE OR REPLACE VIEW public.ml_training_crowd_reports AS
SELECT cr.*
FROM public.crowd_reports cr
JOIN public.profiles p ON p.id = cr.user_id
WHERE p.ml_training_consent = TRUE
  AND cr.user_id IS NOT NULL;

CREATE OR REPLACE VIEW public.ml_training_trip_feedback AS
SELECT tf.*
FROM public.trip_feedback tf
JOIN public.profiles p ON p.id = tf.user_id
WHERE p.ml_training_consent = TRUE
  AND tf.user_id IS NOT NULL;

-- route_choice_feedback is not deployed yet; guard the view so this migration
-- can run before the table exists (it appears automatically once created).
DO $$
BEGIN
  IF to_regclass('public.route_choice_feedback') IS NOT NULL THEN
    EXECUTE $view$
      CREATE OR REPLACE VIEW public.ml_training_route_choice_feedback AS
      SELECT rcf.*
      FROM public.route_choice_feedback rcf
      JOIN public.profiles p ON p.id = rcf.user_id
      WHERE p.ml_training_consent = TRUE
        AND rcf.user_id IS NOT NULL
    $view$;
    EXECUTE 'REVOKE ALL ON public.ml_training_route_choice_feedback FROM anon, authenticated';
  END IF;
END $$;

REVOKE ALL ON public.ml_training_crowd_reports FROM anon, authenticated;
REVOKE ALL ON public.ml_training_trip_feedback FROM anon, authenticated;
