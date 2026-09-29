-- The station catalog is public reference data: allow both anonymous and
-- signed-in (including anonymous-session) users to read it.
DROP POLICY IF EXISTS "Anyone can read train_stops_kl" ON public.train_stops_kl;
CREATE POLICY "Anyone can read train_stops_kl"
  ON public.train_stops_kl
  FOR SELECT
  TO anon, authenticated
  USING (true);
