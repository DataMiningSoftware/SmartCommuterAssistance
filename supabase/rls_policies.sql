-- ============================================================
-- Supabase RLS Policies — Smart Commuter Assistant+ (HARDENED)
-- Applies policies only for tables that exist in the schema.
-- ============================================================

-- Drop existing policies first (safe to re-run)
DO $$ BEGIN
  -- 0. crowd_reports
  IF EXISTS (SELECT FROM information_schema.tables WHERE table_name = 'crowd_reports') THEN
    EXECUTE 'ALTER TABLE crowd_reports ENABLE ROW LEVEL SECURITY';
    EXECUTE 'DROP POLICY IF EXISTS "Anyone can read crowd_reports" ON crowd_reports';
    EXECUTE 'DROP POLICY IF EXISTS "Authenticated users can insert crowd_reports" ON crowd_reports';
    EXECUTE 'DROP POLICY IF EXISTS "Users can update their own crowd_reports" ON crowd_reports';

    EXECUTE 'CREATE POLICY "Anyone can read crowd_reports"
      ON crowd_reports FOR SELECT USING (true)';
    EXECUTE 'CREATE POLICY "Authenticated users can insert crowd_reports"
      ON crowd_reports FOR INSERT WITH CHECK (auth.role() = ''authenticated'')';
    EXECUTE 'CREATE POLICY "Users can update their own crowd_reports"
      ON crowd_reports FOR UPDATE USING (auth.uid() = user_id)';
  END IF;

  -- 1. historical_crowds
  IF EXISTS (SELECT FROM information_schema.tables WHERE table_name = 'historical_crowds') THEN
    EXECUTE 'ALTER TABLE historical_crowds ENABLE ROW LEVEL SECURITY';
    EXECUTE 'DROP POLICY IF EXISTS "Anyone can read historical_crowds" ON historical_crowds';

    EXECUTE 'CREATE POLICY "Anyone can read historical_crowds"
      ON historical_crowds FOR SELECT USING (true)';
  END IF;

  -- 2. crowd_forecast_hourly
  IF EXISTS (SELECT FROM information_schema.tables WHERE table_name = 'crowd_forecast_hourly') THEN
    EXECUTE 'ALTER TABLE crowd_forecast_hourly ENABLE ROW LEVEL SECURITY';
    EXECUTE 'DROP POLICY IF EXISTS "Anyone can read crowd_forecast_hourly" ON crowd_forecast_hourly';

    EXECUTE 'CREATE POLICY "Anyone can read crowd_forecast_hourly"
      ON crowd_forecast_hourly FOR SELECT USING (true)';
  END IF;

  -- 3. profiles
  IF EXISTS (SELECT FROM information_schema.tables WHERE table_name = 'profiles') THEN
    EXECUTE 'ALTER TABLE profiles ENABLE ROW LEVEL SECURITY';
    EXECUTE 'DROP POLICY IF EXISTS "Users can read own profile" ON profiles';
    EXECUTE 'DROP POLICY IF EXISTS "Users can update own profile" ON profiles';

    EXECUTE 'CREATE POLICY "Users can read own profile"
      ON profiles FOR SELECT USING (auth.uid() = id)';
    EXECUTE 'CREATE POLICY "Users can update own profile"
      ON profiles FOR UPDATE USING (auth.uid() = id) WITH CHECK (auth.uid() = id)';
  END IF;

  -- 4. user_preferences
  IF EXISTS (SELECT FROM information_schema.tables WHERE table_name = 'user_preferences') THEN
    EXECUTE 'ALTER TABLE user_preferences ENABLE ROW LEVEL SECURITY';
    EXECUTE 'DROP POLICY IF EXISTS "Users can read own preferences" ON user_preferences';
    EXECUTE 'DROP POLICY IF EXISTS "Users can insert own preferences" ON user_preferences';
    EXECUTE 'DROP POLICY IF EXISTS "Users can update own preferences" ON user_preferences';
    EXECUTE 'DROP POLICY IF EXISTS "Users can delete own preferences" ON user_preferences';

    EXECUTE 'CREATE POLICY "Users can read own preferences"
      ON user_preferences FOR SELECT USING (auth.uid() = user_id)';
    EXECUTE 'CREATE POLICY "Users can insert own preferences"
      ON user_preferences FOR INSERT WITH CHECK (auth.uid() = user_id)';
    EXECUTE 'CREATE POLICY "Users can update own preferences"
      ON user_preferences FOR UPDATE USING (auth.uid() = user_id)';
    EXECUTE 'CREATE POLICY "Users can delete own preferences"
      ON user_preferences FOR DELETE USING (auth.uid() = user_id)';
  END IF;

  -- 5. favorite_routes
  IF EXISTS (SELECT FROM information_schema.tables WHERE table_name = 'favorite_routes') THEN
    EXECUTE 'ALTER TABLE favorite_routes ENABLE ROW LEVEL SECURITY';
    EXECUTE 'DROP POLICY IF EXISTS "Users can read own favorite_routes" ON favorite_routes';
    EXECUTE 'DROP POLICY IF EXISTS "Users can insert own favorite_routes" ON favorite_routes';
    EXECUTE 'DROP POLICY IF EXISTS "Users can delete own favorite_routes" ON favorite_routes';

    EXECUTE 'CREATE POLICY "Users can read own favorite_routes"
      ON favorite_routes FOR SELECT USING (auth.uid() = user_id)';
    EXECUTE 'CREATE POLICY "Users can insert own favorite_routes"
      ON favorite_routes FOR INSERT WITH CHECK (auth.uid() = user_id)';
    EXECUTE 'CREATE POLICY "Users can delete own favorite_routes"
      ON favorite_routes FOR DELETE USING (auth.uid() = user_id)';
  END IF;
END $$;
