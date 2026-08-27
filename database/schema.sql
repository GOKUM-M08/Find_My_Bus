-- SCHOOLS TABLE
create table schools (
  id uuid default gen_random_uuid() primary key,
  name text not null,
  address text,
  phone text,
  email text,
  created_at timestamp default now()
);

-- BUSES TABLE
create table buses (
  id uuid default gen_random_uuid() primary key,
  school_id uuid references schools(id),
  bus_number text not null unique,
  bus_code text,
  driver_name text,
  driver_phone text,
  device_id text unique,        -- GPS tracker device serial number
  capacity integer default 40,
  is_active boolean default true,
  created_at timestamp default now()
);

-- ROUTES TABLE
create table routes (
  id uuid default gen_random_uuid() primary key,
  bus_id uuid references buses(id),
  school_id uuid references schools(id),
  route_name text not null,
  is_active boolean default true,
  created_at timestamp default now()
);

-- STOPS TABLE (ordered stops on a route)
create table stops (
  id uuid default gen_random_uuid() primary key,
  route_id uuid references routes(id),
  stop_name text not null,
  latitude double precision not null,
  longitude double precision not null,
  stop_order integer not null,
  expected_time text,           -- e.g. "07:15 AM"
  created_at timestamp default now()
);

-- STUDENTS TABLE
create table students (
  id uuid default gen_random_uuid() primary key,
  school_id uuid references schools(id),
  bus_id uuid references buses(id),
  stop_id uuid references stops(id),
  student_name text not null,
  parent_name text,
  parent_phone text,
  parent_email text,
  fcm_token text,               -- Firebase push notification token
  created_at timestamp default now()
);

-- LIVE LOCATION TABLE (latest GPS position per bus)
create table live_location (
  id uuid default gen_random_uuid() primary key,
  bus_id uuid references buses(id),
  device_id text,
  latitude double precision,
  longitude double precision,
  speed double precision,
  timestamp timestamp default now()
);

-- LOCATION HISTORY TABLE (full trail)
create table location_history (
  id uuid default gen_random_uuid() primary key,
  bus_id uuid references buses(id),
  latitude double precision,
  longitude double precision,
  speed double precision,
  recorded_at timestamp default now()
);

-- Enable Realtime on live_location table
-- (Go to Supabase → Database → Replication → enable for live_location)

-- ROW LEVEL SECURITY (basic)
alter table schools enable row level security;
alter table buses enable row level security;
alter table routes enable row level security;
alter table stops enable row level security;
alter table students enable row level security;
alter table live_location enable row level security;
alter table location_history enable row level security;

-- Allow read access to all authenticated users
create policy "Allow read" on buses for select using (auth.role() = 'authenticated');
create policy "Allow read" on routes for select using (auth.role() = 'authenticated');
create policy "Allow read" on stops for select using (auth.role() = 'authenticated');
create policy "Allow read" on live_location for select using (auth.role() = 'authenticated');

-- Allow service role full access (your backend)
create policy "Service full access buses" on buses using (auth.role() = 'service_role');
create policy "Service full access live" on live_location using (auth.role() = 'service_role');
create policy "Service full access history" on location_history using (auth.role() = 'service_role');
-- ═════════════════════════════════════════════════════════════════
-- STEP 9.1 — USER ROLES TABLE (added on top of the base schema above)
-- ═════════════════════════════════════════════════════════════════

create table user_roles (
  id uuid default gen_random_uuid() primary key,
  user_id uuid references auth.users(id),
  role text check (role in ('parent', 'driver', 'admin')),
  school_id uuid references schools(id),
  bus_id uuid references buses(id),   -- for drivers only
  created_at timestamp default now()
);

create policy "User reads own role" on user_roles
  for select using (auth.uid() = user_id);

-- After creating a user in Supabase Auth, manually insert their role. Examples:
--
-- Make a user a driver for a specific bus:
-- insert into user_roles (user_id, role, school_id, bus_id)
-- values ('user-uuid-here', 'driver', 'school-uuid', 'bus-uuid');
--
-- Make a user a parent:
-- insert into user_roles (user_id, role, school_id)
-- values ('user-uuid-here', 'parent', 'school-uuid');
