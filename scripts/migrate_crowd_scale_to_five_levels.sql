-- Migrates crowd tables and helper function from the old 0..3 scale
-- to the new app scale:
-- 0 = unknown/delay/legacy sentinel
-- 1 = Empty
-- 2 = Light
-- 3 = Moderate
-- 4 = Heavy
-- 5 = Crowded

do $$
declare
  constraint_name text;
begin
  for constraint_name in
    select con.conname
    from pg_constraint con
    join pg_class rel on rel.oid = con.conrelid
    join pg_namespace nsp on nsp.oid = rel.relnamespace
    where nsp.nspname = 'public'
      and rel.relname = 'crowd_reports'
      and con.contype = 'c'
      and pg_get_constraintdef(con.oid) ilike '%occupancy_level%'
  loop
    execute format(
      'alter table public.crowd_reports drop constraint %I',
      constraint_name
    );
  end loop;
end $$;

do $$
declare
  constraint_name text;
begin
  for constraint_name in
    select con.conname
    from pg_constraint con
    join pg_class rel on rel.oid = con.conrelid
    join pg_namespace nsp on nsp.oid = rel.relnamespace
    where nsp.nspname = 'public'
      and rel.relname = 'crowd_forecast_hourly'
      and con.contype = 'c'
      and pg_get_constraintdef(con.oid) ilike '%occupancy_level%'
  loop
    execute format(
      'alter table public.crowd_forecast_hourly drop constraint %I',
      constraint_name
    );
  end loop;
end $$;

update public.crowd_reports
set occupancy_level = case
  when source_type = 'delay' then 0
  when occupancy_level = 0 then 2
  when occupancy_level = 1 then 3
  when occupancy_level = 2 then 4
  when occupancy_level = 3 then 5
  else occupancy_level
end
where occupancy_level between 0 and 3;

update public.crowd_forecast_hourly
set occupancy_level = case
  when occupancy_level = 0 then 2
  when occupancy_level = 1 then 3
  when occupancy_level = 2 then 4
  when occupancy_level = 3 then 5
  else occupancy_level
end
where occupancy_level between 0 and 3;

alter table public.crowd_reports
  add constraint crowd_reports_occupancy_level_check
  check (occupancy_level between 0 and 5);

alter table public.crowd_forecast_hourly
  add constraint crowd_forecast_hourly_occupancy_level_check
  check (occupancy_level between 0 and 5);

create or replace function public.submit_crowd_report(
  p_stop_id text,
  p_source_type text default 'user',
  p_occupancy_level integer default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_stop_id text := public.normalize_stop_id(p_stop_id);
  v_source_type text := lower(trim(coalesce(p_source_type, 'user')));
  v_occupancy_level smallint;
  v_created_at timestamptz;
begin
  if v_stop_id = '' then
    raise exception 'stop_id is required';
  end if;

  if v_source_type not in ('user', 'delay') then
    raise exception 'Unsupported crowd report source type: %', v_source_type;
  end if;

  if not exists (
    select 1
    from public.transit_stops ts
    where ts.stop_id = v_stop_id
  ) then
    raise exception 'Unknown stop_id: %', v_stop_id;
  end if;

  if exists (
    select 1
    from public.crowd_reports cr
    where cr.stop_id = v_stop_id
      and cr.source_type = v_source_type
      and cr.created_at >= now() - interval '30 seconds'
  ) then
    raise exception 'Please wait before submitting another report for this stop.';
  end if;

  v_occupancy_level := case
    when v_source_type = 'delay' then 0
    else greatest(1, least(coalesce(p_occupancy_level, 3), 5))
  end;

  insert into public.crowd_reports (
    stop_id,
    occupancy_level,
    source_type
  )
  values (
    v_stop_id,
    v_occupancy_level,
    v_source_type
  )
  returning created_at into v_created_at;

  return jsonb_build_object(
    'stop_id', v_stop_id,
    'occupancy_level', v_occupancy_level,
    'source_type', v_source_type,
    'created_at', v_created_at
  );
end;
$$;

grant execute on function public.submit_crowd_report(text, text, integer)
to anon, authenticated;
