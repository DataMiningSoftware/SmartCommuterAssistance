-- ============================================================
-- Smart Commuter Assistant+ — RLS Policies (social / competition / education)
-- Run after migration_profiles.sql, migration_social.sql,
-- migration_competition.sql, migration_education.sql.
-- All write paths that must be trusted go through SECURITY DEFINER
-- RPCs or the backend service role; these policies only expose
-- reads to the correct participants and allow the safe client writes.
-- ============================================================

-- ------------------------------------------------------------------
-- friendships
-- ------------------------------------------------------------------
DROP POLICY IF EXISTS "Users can read own friendships" ON public.friendships;
CREATE POLICY "Users can read own friendships"
  ON public.friendships FOR SELECT TO authenticated
  USING (requester_id = auth.uid() OR addressee_id = auth.uid());

DROP POLICY IF EXISTS "Users can send friend requests" ON public.friendships;
CREATE POLICY "Users can send friend requests"
  ON public.friendships FOR INSERT TO authenticated
  WITH CHECK (requester_id = auth.uid() AND status = 'pending');

DROP POLICY IF EXISTS "Users can respond to friend requests" ON public.friendships;
CREATE POLICY "Users can respond to friend requests"
  ON public.friendships FOR UPDATE TO authenticated
  USING (addressee_id = auth.uid() AND status = 'pending')
  WITH CHECK (status IN ('accepted', 'declined'));

DROP POLICY IF EXISTS "Users can remove friendships" ON public.friendships;
CREATE POLICY "Users can remove friendships"
  ON public.friendships FOR DELETE TO authenticated
  USING (requester_id = auth.uid() OR addressee_id = auth.uid());

-- ------------------------------------------------------------------
-- parties
-- ------------------------------------------------------------------
DROP POLICY IF EXISTS "Authenticated users can read parties" ON public.parties;
CREATE POLICY "Authenticated users can read parties"
  ON public.parties FOR SELECT TO authenticated USING (true);

DROP POLICY IF EXISTS "Owners can update parties" ON public.parties;
CREATE POLICY "Owners can update parties"
  ON public.parties FOR UPDATE TO authenticated
  USING (owner_id = auth.uid());

DROP POLICY IF EXISTS "Owners can delete parties" ON public.parties;
CREATE POLICY "Owners can delete parties"
  ON public.parties FOR DELETE TO authenticated
  USING (owner_id = auth.uid());

-- ------------------------------------------------------------------
-- party_members (read only for members; writes via RPC)
-- ------------------------------------------------------------------
DROP POLICY IF EXISTS "Members can read party members" ON public.party_members;
CREATE POLICY "Members can read party members"
  ON public.party_members FOR SELECT TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.party_members me
      WHERE me.party_id = party_members.party_id
        AND me.user_id = auth.uid()
        AND me.left_at IS NULL
    )
  );

-- ------------------------------------------------------------------
-- races (read only for party members; writes via backend service role)
-- ------------------------------------------------------------------
DROP POLICY IF EXISTS "Party members can read races" ON public.races;
CREATE POLICY "Party members can read races"
  ON public.races FOR SELECT TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.party_members pm
      WHERE pm.party_id = races.party_id
        AND pm.user_id = auth.uid()
        AND pm.left_at IS NULL
    )
  );

-- ------------------------------------------------------------------
-- race_participants
-- ------------------------------------------------------------------
DROP POLICY IF EXISTS "Party members can read race participants" ON public.race_participants;
CREATE POLICY "Party members can read race participants"
  ON public.race_participants FOR SELECT TO authenticated
  USING (
    EXISTS (
      SELECT 1
      FROM public.races r
      JOIN public.party_members pm ON pm.party_id = r.party_id
      WHERE r.id = race_participants.race_id
        AND pm.user_id = auth.uid()
        AND pm.left_at IS NULL
    )
  );

-- ------------------------------------------------------------------
-- race_checkpoints
-- ------------------------------------------------------------------
DROP POLICY IF EXISTS "Party members can read race checkpoints" ON public.race_checkpoints;
CREATE POLICY "Party members can read race checkpoints"
  ON public.race_checkpoints FOR SELECT TO authenticated
  USING (
    EXISTS (
      SELECT 1
      FROM public.races r
      JOIN public.party_members pm ON pm.party_id = r.party_id
      WHERE r.id = race_checkpoints.race_id
        AND pm.user_id = auth.uid()
        AND pm.left_at IS NULL
    )
  );

-- ------------------------------------------------------------------
-- route_choice_feedback
-- ------------------------------------------------------------------
DROP POLICY IF EXISTS "Users can read own route feedback" ON public.route_choice_feedback;
CREATE POLICY "Users can read own route feedback"
  ON public.route_choice_feedback FOR SELECT TO authenticated
  USING (user_id = auth.uid());

DROP POLICY IF EXISTS "Users can insert own route feedback" ON public.route_choice_feedback;
CREATE POLICY "Users can insert own route feedback"
  ON public.route_choice_feedback FOR INSERT TO authenticated
  WITH CHECK (user_id = auth.uid());

-- ------------------------------------------------------------------
-- station_lore (public read; content seeded by service role)
-- ------------------------------------------------------------------
DROP POLICY IF EXISTS "Anyone can read station lore" ON public.station_lore;
CREATE POLICY "Anyone can read station lore"
  ON public.station_lore FOR SELECT USING (true);

-- ------------------------------------------------------------------
-- quiz_attempts
-- ------------------------------------------------------------------
DROP POLICY IF EXISTS "Users can read own quiz attempts" ON public.quiz_attempts;
CREATE POLICY "Users can read own quiz attempts"
  ON public.quiz_attempts FOR SELECT TO authenticated
  USING (user_id = auth.uid());

DROP POLICY IF EXISTS "Users can insert own quiz attempts" ON public.quiz_attempts;
CREATE POLICY "Users can insert own quiz attempts"
  ON public.quiz_attempts FOR INSERT TO authenticated
  WITH CHECK (user_id = auth.uid());
