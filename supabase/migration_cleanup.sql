-- ============================================================
-- Smart Commuter Assistant+ — Database Cleanup Migration
-- Run this in Supabase SQL Editor (Dashboard > SQL Editor)
-- ============================================================

-- 1. DROP the old 3-parameter overload of submit_crowd_report
--    (7-param version with defaults replaces it).
DROP FUNCTION IF EXISTS submit_crowd_report(TEXT, TEXT, INT) CASCADE;

-- 2. DROP the dead transit_stops table (app uses train_stops_kl).
--    Note: user_id / latitude / longitude / session_id on crowd_reports are
--    NOT dropped — they are populated by the backend geo-fence + rate-limit
--    flow (see migration_crowd_system.sql and backend/crowd_service.py).
DROP TABLE IF EXISTS transit_stops CASCADE;

-- 3. Verify cleanup
SELECT column_name, data_type, is_nullable
FROM information_schema.columns
WHERE table_name = 'crowd_reports'
ORDER BY ordinal_position;
