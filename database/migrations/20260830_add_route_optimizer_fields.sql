-- Route Optimizer inputs. Safe to run against an existing Supabase project.
alter table buses
  add column if not exists mileage_kmpl double precision,
  add column if not exists capacity integer default 40,
  add column if not exists condition_score double precision default 1.0,
  add column if not exists diesel_price_per_l double precision;

alter table buses
  drop constraint if exists buses_condition_score_range,
  add constraint buses_condition_score_range
    check (condition_score between 0 and 1);

alter table routes
  add column if not exists distance_km double precision,
  add column if not exists student_count integer,
  add column if not exists traffic_index double precision default 1.0;

alter table routes
  drop constraint if exists routes_traffic_index_positive,
  add constraint routes_traffic_index_positive check (traffic_index > 0);

-- Existing data remains usable with these conservative defaults. Administrators
-- should replace them with real vehicle and route measurements before relying on
-- optimization recommendations.
update buses set condition_score = 1.0 where condition_score is null;
update routes set traffic_index = 1.0 where traffic_index is null;
