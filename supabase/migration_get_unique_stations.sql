-- ============================================================
-- Smart Commuter Assistant+ — get_unique_stations RPC
-- Returns one row per station name with the set of rail lines that
-- serve it. Used by the Stations screen to show per-station line badges.
-- ============================================================

CREATE OR REPLACE FUNCTION public.get_unique_stations()
RETURNS TABLE (station_name TEXT, lines TEXT[])
LANGUAGE sql
STABLE
AS $$
  SELECT
    trim(coalesce(ts.stop_name, '')) AS station_name,
    array_agg(DISTINCT upper(trim(coalesce(ts.route_id, ''))))
      FILTER (WHERE upper(trim(coalesce(ts.route_id, ''))) <> '') AS lines
  FROM public.train_stops_kl ts
  WHERE trim(coalesce(ts.stop_name, '')) <> ''
  GROUP BY trim(coalesce(ts.stop_name, ''))
  ORDER BY station_name;
$$;
