-- Finds the cheapest route path from start_stop to end_stop using route_connections.
-- This is the RPC expected by lib/screens/stations_screen.dart.

create or replace function public.find_route(start_stop text, end_stop text)
returns table(path_array text[], total_time integer)
language sql
security definer
set search_path = public
as $$
  with recursive paths as (
    select
      array[upper(trim(rc.from_stop_id)), upper(trim(rc.to_stop_id))]::text[] as path_array,
      upper(trim(rc.to_stop_id)) as current_stop,
      rc.travel_time_minutes as total_time,
      1 as depth
    from public.route_connections rc
    where upper(trim(rc.from_stop_id)) = upper(trim(start_stop))

    union all

    select
      p.path_array || upper(trim(rc.to_stop_id)),
      upper(trim(rc.to_stop_id)) as current_stop,
      p.total_time + rc.travel_time_minutes as total_time,
      p.depth + 1 as depth
    from paths p
    join public.route_connections rc
      on upper(trim(rc.from_stop_id)) = p.current_stop
    where p.depth < 40
      and not (upper(trim(rc.to_stop_id)) = any (p.path_array))
  )
  select
    path_array,
    total_time
  from paths
  where current_stop = upper(trim(end_stop))
  order by total_time asc, cardinality(path_array) asc
  limit 1;
$$;

grant execute on function public.find_route(text, text) to anon, authenticated;
