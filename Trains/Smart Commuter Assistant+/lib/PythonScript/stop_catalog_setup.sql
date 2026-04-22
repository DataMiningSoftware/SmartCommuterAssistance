-- Canonical stop catalog used by route/crowd tables for referential integrity.
-- Run this after train_stops_kl is populated.

create or replace function public.normalize_stop_id(value text)
returns text
language sql
immutable
as $$
  select upper(trim(coalesce(value, '')))
$$;

create table if not exists public.transit_stops (
  stop_id text primary key,
  stop_name text not null,
  stop_lat double precision,
  stop_lon double precision,
  route_id text not null,
  category text,
  synced_at timestamptz not null default now()
);

create index if not exists idx_transit_stops_route_id
on public.transit_stops (route_id);

insert into public.transit_stops (
  stop_id,
  stop_name,
  stop_lat,
  stop_lon,
  route_id,
  category,
  synced_at
)
select distinct on (public.normalize_stop_id(ts.stop_id))
  public.normalize_stop_id(ts.stop_id) as stop_id,
  trim(coalesce(ts.stop_name, public.normalize_stop_id(ts.stop_id))) as stop_name,
  ts.stop_lat,
  ts.stop_lon,
  upper(trim(coalesce(ts.route_id, 'N/A'))) as route_id,
  nullif(trim(coalesce(ts.category, '')), '') as category,
  now() as synced_at
from public.train_stops_kl ts
where public.normalize_stop_id(ts.stop_id) <> ''
order by public.normalize_stop_id(ts.stop_id), trim(coalesce(ts.stop_name, ''))
on conflict (stop_id) do update
set
  stop_name = excluded.stop_name,
  stop_lat = excluded.stop_lat,
  stop_lon = excluded.stop_lon,
  route_id = excluded.route_id,
  category = excluded.category,
  synced_at = now();
