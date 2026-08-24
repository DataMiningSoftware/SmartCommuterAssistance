-- Finds the cheapest route path from start_stop to end_stop using route_connections.
-- This is the RPC expected by lib/screens/stations_screen.dart.

create or replace function public.find_route(start_stop text, end_stop text)
returns table(path_array text[], total_time integer)
language sql
security definer
set search_path = public
as $$
  with recursive params as (
    select
      public.normalize_stop_id(start_stop) as start_id,
      public.normalize_stop_id(end_stop) as end_id
  ),
  paths as (
    select
      array[rc.from_stop_id, rc.to_stop_id]::text[] as path_array,
      rc.to_stop_id as current_stop,
      rc.travel_time_minutes as total_time,
      1 as depth
    from public.route_connections rc
    join params p on rc.from_stop_id = p.start_id

    union all

    select
      path.path_array || rc.to_stop_id,
      rc.to_stop_id as current_stop,
      path.total_time + rc.travel_time_minutes as total_time,
      path.depth + 1 as depth
    from paths path
    join public.route_connections rc
      on rc.from_stop_id = path.current_stop
    where path.depth < 40
      and not (rc.to_stop_id = any (path.path_array))
  )
  select
    path.path_array,
    path.total_time
  from paths path
  join params p on true
  where path.current_stop = p.end_id
  order by total_time asc, cardinality(path_array) asc
  limit 1;
$$;

grant execute on function public.find_route(text, text) to anon, authenticated;
