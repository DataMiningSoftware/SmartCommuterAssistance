-- Adds the ERL services (line 6 KLIA Ekspres, line 7 KLIA Transit) to route_connections.
-- The original insert_connections.sql seed stops at Putrajaya Sentral, which makes PY41
-- a dead end and hides KLIA Transit from the planner.
--
-- Safe to re-run: each row is inserted only when the exact edge does not already exist.

insert into route_connections
  (from_stop_id, to_stop_id, route_id, connection_type, travel_time_minutes)
select v.from_stop_id, v.to_stop_id, v.route_id, v.connection_type, v.travel_time_minutes
from (values
  ('KJ15', 'KLIA',         'ER6', 'standard_stop', 28),
  ('KLIA', 'KJ15',         'ER6', 'standard_stop', 28),
  ('KLIA', 'KLIA2',        'ER6', 'standard_stop',  3),
  ('KLIA2', 'KLIA',        'ER6', 'standard_stop',  3),
  ('KJ15', 'SP15',         'ER7', 'standard_stop',  7),
  ('SP15', 'KJ15',         'ER7', 'standard_stop',  7),
  ('SP15', 'PY41',         'ER7', 'standard_stop', 12),
  ('PY41', 'SP15',         'ER7', 'standard_stop', 12),
  ('PY41', 'SALAK_TINGGI', 'ER7', 'standard_stop', 10),
  ('SALAK_TINGGI', 'PY41', 'ER7', 'standard_stop', 10),
  ('SALAK_TINGGI', 'KLIA', 'ER7', 'standard_stop',  7),
  ('KLIA', 'SALAK_TINGGI', 'ER7', 'standard_stop',  7)
) as v(from_stop_id, to_stop_id, route_id, connection_type, travel_time_minutes)
where not exists (
  select 1
  from route_connections rc
  where rc.from_stop_id = v.from_stop_id
    and rc.to_stop_id = v.to_stop_id
    and rc.route_id = v.route_id
);

select route_id, count(*) as edges
from route_connections
where route_id in ('ER6', 'ER7')
group by route_id
order by route_id;
