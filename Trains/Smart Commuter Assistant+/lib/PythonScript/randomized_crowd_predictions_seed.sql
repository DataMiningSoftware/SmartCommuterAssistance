-- Randomized crowd seed for all stations.
-- Run this after crowd_reports_setup.sql to quickly populate crowd reports.
-- It inserts several recent samples per station and creates a simple trend view.

insert into public.crowd_reports (
  stop_id,
  occupancy_level,
  source_type,
  created_at
)
select
  s.stop_id,
  case
    when rnd < 0.18 then 0
    when rnd < 0.52 then 1
    when rnd < 0.82 then 2
    else 3
  end as occupancy_level,
  case
    when random() < 0.30 then 'user'
    else 'predicted'
  end as source_type,
  now() - ((g.sample_no - 1) * interval '10 minutes')
from (
  select distinct upper(trim(stop_id)) as stop_id
  from public.train_stops_kl
  where stop_id is not null
    and trim(stop_id) <> ''
) s
cross join lateral generate_series(1, 6) as g(sample_no)
cross join lateral (
  select random() as rnd
) r;

create or replace view public.station_crowd_trend as
select
  stop_id,
  count(*) as sample_count,
  count(*) filter (where source_type = 'user') as user_report_count,
  round(avg(occupancy_level)::numeric, 2) as avg_level_24h,
  max(created_at) as latest_report_at
from public.crowd_reports
where created_at >= now() - interval '24 hours'
group by stop_id;
