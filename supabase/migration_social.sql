-- ============================================================
-- Smart Commuter Assistant+ — Social Migration
-- Friendships + Parties + Party members, with server-side RPCs
-- that enforce membership/lifecycle rules (never trusted from client).
-- ============================================================

-- ------------------------------------------------------------------
-- FRIENDSHIPS (single relationship row per unordered user pair)
-- ------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.friendships (
  id           BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  requester_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  addressee_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  status       TEXT NOT NULL DEFAULT 'pending'
                 CHECK (status IN ('pending', 'accepted', 'declined')),
  created_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
  CHECK (requester_id <> addressee_id)
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_friendships_pair
  ON public.friendships (LEAST(requester_id, addressee_id), GREATEST(requester_id, addressee_id));

CREATE INDEX IF NOT EXISTS idx_friendships_addressee
  ON public.friendships (addressee_id, status);

CREATE INDEX IF NOT EXISTS idx_friendships_requester
  ON public.friendships (requester_id, status);

-- ------------------------------------------------------------------
-- PARTIES
-- ------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.parties (
  id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  join_code  TEXT UNIQUE NOT NULL,
  owner_id   UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  state      TEXT NOT NULL DEFAULT 'open'
               CHECK (state IN ('open', 'active', 'closed')),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  expires_at TIMESTAMPTZ NOT NULL DEFAULT (now() + INTERVAL '24 hours')
);

CREATE INDEX IF NOT EXISTS idx_parties_state ON public.parties (state, expires_at);

-- ------------------------------------------------------------------
-- PARTY MEMBERS (latest position only — no history)
-- ------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.party_members (
  id                 BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  party_id           UUID NOT NULL REFERENCES public.parties(id) ON DELETE CASCADE,
  user_id            UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  current_station_id TEXT,
  joined_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
  left_at            TIMESTAMPTZ,
  UNIQUE (party_id, user_id)
);

CREATE INDEX IF NOT EXISTS idx_party_members_party ON public.party_members (party_id);

-- ==================================================================
-- SERVER-SIDE RPCs (SECURITY DEFINER enforces lifecycle rules)
-- ==================================================================

-- Search users by handle / display name, respecting privacy toggle.
CREATE OR REPLACE FUNCTION public.search_users(p_query TEXT)
RETURNS TABLE (
  id UUID, handle TEXT, display_name TEXT, avatar_url TEXT,
  avatar_color TEXT, bio TEXT
)
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT p.id, p.handle, p.display_name, p.avatar_url, p.avatar_color, p.bio
  FROM public.profiles p
  WHERE p.allow_handle_search = TRUE
    AND p.id <> auth.uid()
    AND (
      lower(p.handle) LIKE '%' || lower(trim(p_query)) || '%'
      OR lower(coalesce(p.display_name, '')) LIKE '%' || lower(trim(p_query)) || '%'
    )
  ORDER BY p.handle
  LIMIT 20;
$$;

-- List confirmed friends with public profile info.
CREATE OR REPLACE FUNCTION public.get_friends()
RETURNS TABLE (
  user_id UUID, handle TEXT, display_name TEXT, avatar_url TEXT,
  avatar_color TEXT, home_station_id TEXT, favorite_line TEXT
)
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT
    p.id, p.handle, p.display_name, p.avatar_url, p.avatar_color,
    p.home_station_id, p.favorite_line
  FROM public.friendships f
  JOIN public.profiles p
    ON p.id = CASE WHEN f.requester_id = auth.uid() THEN f.addressee_id ELSE f.requester_id END
  WHERE (f.requester_id = auth.uid() OR f.addressee_id = auth.uid())
    AND f.status = 'accepted';
$$;

-- Create a party (caller becomes owner + first member). Closes any
-- existing open/active party the caller owns or belongs to.
CREATE OR REPLACE FUNCTION public.create_party(p_join_code TEXT)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_party_id UUID;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'authentication required';
  END IF;

  DELETE FROM public.party_members pm
  USING public.parties p
  WHERE pm.party_id = p.id
    AND pm.user_id = auth.uid()
    AND p.state IN ('open', 'active');

  UPDATE public.parties
  SET state = 'closed', updated_at = now()
  WHERE owner_id = auth.uid() AND state IN ('open', 'active');

  INSERT INTO public.parties (join_code, owner_id)
  VALUES (upper(trim(p_join_code)), auth.uid())
  RETURNING id INTO v_party_id;

  INSERT INTO public.party_members (party_id, user_id)
  VALUES (v_party_id, auth.uid());

  RETURN v_party_id;
END;
$$;

-- Join a party by code (enforces open state + expiry + one-active-party).
CREATE OR REPLACE FUNCTION public.join_party(p_join_code TEXT)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_party public.parties%ROWTYPE;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'authentication required';
  END IF;

  SELECT * INTO v_party
  FROM public.parties
  WHERE upper(join_code) = upper(trim(p_join_code))
  ORDER BY created_at DESC
  LIMIT 1;

  IF v_party.id IS NULL THEN
    RAISE EXCEPTION 'party not found';
  END IF;
  IF v_party.state <> 'open' THEN
    RAISE EXCEPTION 'party is not accepting joins';
  END IF;
  IF v_party.expires_at < now() THEN
    RAISE EXCEPTION 'party expired';
  END IF;

  DELETE FROM public.party_members pm
  USING public.parties p
  WHERE pm.party_id = p.id
    AND pm.user_id = auth.uid()
    AND p.state IN ('open', 'active')
    AND pm.party_id <> v_party.id;

  INSERT INTO public.party_members (party_id, user_id)
  VALUES (v_party.id, auth.uid())
  ON CONFLICT (party_id, user_id) DO NOTHING;

  RETURN v_party.id;
END;
$$;

-- Leave a party (closes it if it ends up empty).
CREATE OR REPLACE FUNCTION public.leave_party(p_party_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  DELETE FROM public.party_members
  WHERE party_id = p_party_id AND user_id = auth.uid();

  IF NOT EXISTS (SELECT 1 FROM public.party_members WHERE party_id = p_party_id) THEN
    UPDATE public.parties
    SET state = 'closed', updated_at = now()
    WHERE id = p_party_id;
  END IF;
END;
$$;

-- Update the caller's coarse location (nearest station) in a party.
-- Only the latest position is stored.
CREATE OR REPLACE FUNCTION public.set_party_location(p_party_id UUID, p_station_id TEXT)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_count INT;
BEGIN
  SELECT COUNT(*) INTO v_count
  FROM public.party_members
  WHERE party_id = p_party_id AND user_id = auth.uid() AND left_at IS NULL;

  IF v_count = 0 THEN
    RAISE EXCEPTION 'not a member of this party';
  END IF;

  UPDATE public.party_members
  SET current_station_id = p_station_id
  WHERE party_id = p_party_id AND user_id = auth.uid();
END;
$$;

-- Close a party (owner only).
CREATE OR REPLACE FUNCTION public.close_party(p_party_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  UPDATE public.parties
  SET state = 'closed', updated_at = now()
  WHERE id = p_party_id AND owner_id = auth.uid();

  DELETE FROM public.party_members WHERE party_id = p_party_id;
END;
$$;

ALTER TABLE public.friendships ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.parties ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.party_members ENABLE ROW LEVEL SECURITY;

-- Realtime: party membership + location stream.
ALTER PUBLICATION supabase_realtime ADD TABLE public.parties;
ALTER PUBLICATION supabase_realtime ADD TABLE public.party_members;
