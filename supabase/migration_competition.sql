-- ============================================================
-- Smart Commuter Assistant+ — Competition Migration
-- Races, participants, checkpoints (with plausibility flag), and
-- route-choice feedback for the "manual vs agent" learning loop.
-- ============================================================

-- ------------------------------------------------------------------
-- RACES
-- ------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.races (
  id                   UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  party_id             UUID NOT NULL REFERENCES public.parties(id) ON DELETE CASCADE,
  category             TEXT NOT NULL
                         CHECK (category IN ('fastest', 'comfort', 'efficient')),
  target_mode          TEXT NOT NULL DEFAULT 'shared_destination'
                         CHECK (target_mode IN ('shared_destination', 'per_participant_destination')),
  destination_stop_id  TEXT,
  status               TEXT NOT NULL DEFAULT 'countdown'
                         CHECK (status IN ('countdown', 'active', 'finished', 'cancelled')),
  started_at           TIMESTAMPTZ,
  ended_at             TIMESTAMPTZ,
  created_at           TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_races_party ON public.races (party_id, status);

-- ------------------------------------------------------------------
-- RACE PARTICIPANTS
-- ------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.race_participants (
  id                  BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  race_id             UUID NOT NULL REFERENCES public.races(id) ON DELETE CASCADE,
  user_id             UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  destination_stop_id TEXT,
  route_source        TEXT NOT NULL DEFAULT 'agent'
                        CHECK (route_source IN ('agent', 'manual')),
  agent_path          TEXT,
  chosen_path         TEXT,
  agent_predicted_min INTEGER,
  status              TEXT NOT NULL DEFAULT 'ready'
                        CHECK (status IN ('ready', 'racing', 'finished', 'dnf')),
  result_value        NUMERIC,
  rank                INTEGER,
  finished_at         TIMESTAMPTZ,
  created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (race_id, user_id)
);

CREATE INDEX IF NOT EXISTS idx_race_participants_race ON public.race_participants (race_id, status);

-- ------------------------------------------------------------------
-- RACE CHECKPOINTS (station-by-station; plausibility set server-side)
-- ------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.race_checkpoints (
  id            BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  race_id       UUID NOT NULL REFERENCES public.races(id) ON DELETE CASCADE,
  user_id       UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  station_id    TEXT NOT NULL,
  seq           INTEGER NOT NULL,
  crowd_level   SMALLINT CHECK (crowd_level BETWEEN 0 AND 5),
  reached_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
  plausibility  TEXT NOT NULL DEFAULT 'ok'
                  CHECK (plausibility IN ('ok', 'disputed', 'pending')),
  UNIQUE (race_id, user_id, seq)
);

CREATE INDEX IF NOT EXISTS idx_race_checkpoints_race
  ON public.race_checkpoints (race_id, user_id, seq);

-- ------------------------------------------------------------------
-- ROUTE CHOICE FEEDBACK (manual-vs-agent comparison for retraining)
-- ------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.route_choice_feedback (
  id                  BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  user_id             UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  race_id             UUID,
  route_id            TEXT,
  origin_stop         TEXT NOT NULL,
  dest_stop           TEXT NOT NULL,
  agent_path          TEXT,
  chosen_path         TEXT,
  agent_predicted_min INTEGER,
  chosen_actual_min   INTEGER,
  route_source        TEXT NOT NULL CHECK (route_source IN ('agent', 'manual')),
  created_at          TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_route_choice_feedback_user
  ON public.route_choice_feedback (user_id, created_at DESC);

-- Participant sets their own plan (destination / route source / path).
-- Deliberately excludes status, rank and result_value so a client can
-- never self-award a finish — that stays server-side.
CREATE OR REPLACE FUNCTION public.set_race_plan(
  p_race_id UUID,
  p_destination_stop_id TEXT,
  p_route_source TEXT,
  p_chosen_path TEXT,
  p_agent_path TEXT,
  p_agent_predicted_min INTEGER
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_count INT;
BEGIN
  SELECT COUNT(*) INTO v_count
  FROM public.race_participants
  WHERE race_id = p_race_id AND user_id = auth.uid();

  IF v_count = 0 THEN
    RAISE EXCEPTION 'not a participant in this race';
  END IF;

  UPDATE public.race_participants
  SET destination_stop_id = p_destination_stop_id,
      route_source = p_route_source,
      chosen_path = p_chosen_path,
      agent_path = p_agent_path,
      agent_predicted_min = p_agent_predicted_min
  WHERE race_id = p_race_id AND user_id = auth.uid();
END;
$$;

ALTER TABLE public.races ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.race_participants ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.race_checkpoints ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.route_choice_feedback ENABLE ROW LEVEL SECURITY;

-- Realtime: race lifecycle + checkpoint stream.
ALTER PUBLICATION supabase_realtime ADD TABLE public.races;
ALTER PUBLICATION supabase_realtime ADD TABLE public.race_participants;
ALTER PUBLICATION supabase_realtime ADD TABLE public.race_checkpoints;
