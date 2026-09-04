-- Phase 1 Schema Migration for Route Optimizer & Fleet Analytics

-- 1. Add admin-entered route condition fields to routes table
alter table routes
  add column if not exists traffic_level text check (traffic_level in ('low', 'medium', 'high')),
  add column if not exists num_speed_breakers integer,
  add column if not exists num_narrow_road_sections integer,
  add column if not exists road_quality text check (road_quality in ('good', 'moderate', 'poor')),
  add column if not exists avg_speed_kmph double precision,
  add column if not exists peak_congestion_window text;

-- 2. Add fleet physical attributes to buses table
alter table buses
  add column if not exists bus_type text check (bus_type in ('large', 'medium', 'small')),
  add column if not exists age_years integer,
  add column if not exists suitable_for_narrow_roads boolean;

-- 3. Create stop_student_counts table
create table if not exists stop_student_counts (
  id uuid default gen_random_uuid() primary key,
  stop_id uuid references stops(id) on delete cascade,
  student_count integer default 0,
  created_at timestamp default now()
);

-- Enable RLS on stop_student_counts
alter table stop_student_counts enable row level security;
create policy "Allow read stop_student_counts" on stop_student_counts for select using (auth.role() = 'authenticated');
create policy "Service full access stop_student_counts" on stop_student_counts using (auth.role() = 'service_role');
