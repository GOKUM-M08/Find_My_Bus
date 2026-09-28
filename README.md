# BusTrack (Find My Bus)

School bus tracking system — Flutter parent/driver app, a standalone Flutter
**web** admin console, a FastAPI backend, Supabase + Redis (Upstash) for
data/caching, Firebase Cloud Messaging for push notifications, and a Google
Gemini–powered route optimization layer.

This project was originally assembled from `BUSTRACK_COMPLETE_GUIDE.md`.
Since then the admin experience has been fully rebuilt in Flutter and split
out into its own hosted web app — see **"Admin console rebuild"** below for
what changed and why. The original React admin panel (`admin_panel/`) is
left untouched and unused going forward, kept only for reference.

## Live deployments

- **Admin console (web):** https://gokum-m08.github.io/findmybus-admin/
- **Backend API:** https://find-my-bus-teu4.onrender.com
- **Parent/driver app:** distributed as an Android APK (not yet on a store
  listing)

## Folder structure

```
bustrack/
├── backend/                FastAPI server
│   ├── main.py
│   ├── gps_listener.py         TCP listener for AIS 140 GPS devices
│   ├── traccar_forward.py      HTTP endpoint for Traccar-forwarded GT06 positions
│   ├── database.py             Supabase + Redis clients (service_role key)
│   ├── notifications.py        Firebase push notification sender
│   ├── models.py
│   ├── auth.py
│   ├── simulate_bus.py         Test script — simulates a bus without hardware
│   ├── requirements.txt
│   ├── .env.example
│   ├── routes/
│   │   ├── buses.py                fuel-metrics + bus-attribute + route-reassignment endpoints
│   │   ├── tracking.py             live location + history + ETA + trip-direction override
│   │   ├── students.py
│   │   ├── schools.py
│   │   └── route_optimizer.py      Hungarian algorithm + Gemini explanation layer
│   └── jobs/
│       ├── monthly_data_aggregation.py   scheduled snapshot job (scaffolding, live)
│       └── retrain_model.py              training stub — waits for enough monthly snapshots
│
├── flutter_app/             Parent/driver mobile app + standalone admin web app
│   │                        (same codebase, two entry points — see below)
│   ├── pubspec.yaml
│   ├── assets/
│   │   └── icon/                 shared app logo, reused by both mobile app and admin console
│   ├── lib/
│   │   ├── main.dart             Parent/driver mobile entry point — zero admin code
│   │   ├── main_admin.dart       Admin web entry point — builds to the hosted admin console
│   │   ├── screens/
│   │   │   ├── find_bus_screen.dart        parent home screen (bus search, driver-login icon)
│   │   │   ├── tracking_screen.dart        live map + ETA + notification subscribe/unsubscribe
│   │   │   ├── driver_screen.dart          phone-as-GPS-tracker
│   │   │   ├── register_student_screen.dart
│   │   │   ├── admin_login_screen.dart
│   │   │   ├── admin_dashboard_screen.dart     KPIs, overspeed/service-due counts, AI Fleet Insights panel
│   │   │   ├── bus_profile_screen.dart         bus CRUD, maintenance tracking, live map
│   │   │   ├── route_management_screen.dart    route/stop CRUD, bus reassignment, route condition editor
│   │   │   ├── fuel_mileage_screen.dart        fuel cost / mileage baseline vs. real-world efficiency
│   │   │   ├── route_optimizer_screen.dart     Hungarian assignments + Gemini plain-English explanations
│   │   │   └── settings_screen.dart            system health, trip-direction override, audit log viewer
│   │   ├── widgets/
│   │   │   └── admin_drawer.dart
│   │   └── services/
│   │       └── notification_service.dart
│   ├── android/app/src/main/AndroidManifest.xml
│   ├── ios/, macos/, linux/, windows/, web/    platform targets
│   └── test/
│
├── admin_panel/              Original React admin dashboard — UNTOUCHED, superseded by
│   │                         the Flutter admin console above, kept for reference only
│   ├── package.json
│   ├── public/index.html
│   └── src/
│       ├── App.jsx
│       ├── supabaseClient.js
│       └── components/
│           ├── BusMap.jsx
│           ├── AddBus.jsx
│           ├── RouteBuilder.jsx
│           └── StudentList.jsx
│
└── database/
    ├── schema.sql                                  base schema (STEP 9.1 onward)
    └── migrations/
        ├── 20260926_add_maintenance_and_audit_logs.sql
        └── 20260927_add_route_condition_ai_columns.sql
```

## Admin console rebuild

The original plan was two separate admin interfaces (React web + partial
Flutter mobile screens), both with non-functional buttons and placeholder
data. That was scrapped and rebuilt as a **single new Flutter admin
console**, built from the same codebase as the parent app but compiled
through a **separate entry point** so the two ship as independent artifacts:

- `flutter build apk --release` → parent/driver mobile app.
  Built from `lib/main.dart`. Contains **no** admin screens, imports, or
  routes — confirmed by package-size analysis (`package:bustrack` dropped
  from 366 KB to 179 KB, and the `fl_chart` charting dependency disappears
  entirely) after a stray navigation link inside `find_bus_screen.dart`
  was found and removed.
- `flutter build web -t lib/main_admin.dart --base-href /findmybus-admin/`
  → the admin console, deployed as a static site to GitHub Pages at
  https://gokum-m08.github.io/findmybus-admin/. Built from
  `lib/main_admin.dart`, which starts on `AdminLoginScreen` and pulls in
  the same admin screen files listed in the folder structure above.

Splitting these was a deliberate architecture decision, not a size
optimization (a Flutter APK's ~18–20 MB is almost entirely the Flutter
engine itself, not app code) — it means admin fixes can deploy to GitHub
Pages independently of an app-store release cycle, and admin-only logic
isn't shipped to every parent's phone.

**Reused, not duplicated:** every admin screen file lives once, under
`flutter_app/lib/screens/`. `main_admin.dart` imports them for the web
build; `main.dart` does not reference them at all.

### What the admin console does

Full CRUD, real Supabase data throughout (no mock/placeholder data
anywhere):

- **Bus management** — registration, IMEI/device_id, capacity, maintenance
  dates (`last_service_date`, `next_service_due_date`,
  `next_service_due_km`, `current_odometer_km`), live map.
- **Route management** — stops (add/edit/reorder/remove), immediate bus
  reassignment (`bus_id` update takes effect live), and a **route
  condition editor**: `speed_breaker_count`, `sharp_turn_count`,
  `traffic_level` (low/medium/high), `road_quality` (good/average/poor) —
  added directly to the existing `routes` table.
- **Student management** — CRUD, bus/stop assignment, searchable/filterable
  roster, responsive table (desktop) / card list (mobile).
- **Fuel & mileage tracking** — admin-set baseline (`diesel_price_per_l`,
  `mileage_kmpl`, `diesel_tank_capacity`) as the foundation for future
  diesel-fraud detection; the detection logic itself is not yet built.
- **Route Optimizer** — the Hungarian-algorithm engine in
  `backend/routes/route_optimizer.py` remains the deterministic ranking
  authority. Scoring now uses an **adjusted effective distance**, not raw
  distance:

  ```
  D_eff = (raw_distance_km + 0.15 × speed_breaker_count + 0.10 × sharp_turn_count)
          × traffic_mult × road_quality_mult
  T_eff = D_eff / 40.0 km/h
  ```
  `traffic_mult`: low 1.0, medium 1.15, high 1.30.
  `road_quality_mult`: good 1.0, average/moderate 1.10, poor 1.25.

  Monthly fuel-cost savings are calculated deterministically in Python
  (distance difference ÷ mileage baseline × diesel price, × 22 operating
  days/month). **Google Gemini (1.5 Flash, free tier)** is called
  server-side only to turn these already-computed numbers into a
  plain-English explanation per recommendation — the prompt explicitly
  forbids Gemini from inventing or altering any figure. `GEMINI_API_KEY`
  lives in `backend/.env`; if it's unset, the endpoint falls back to a
  template sentence instead of crashing.
- **Dashboard** — live fleet KPIs (active count, >60 km/h overspeed count,
  service-due count) and an **AI Fleet Insights panel** showing the same
  Gemini-generated explanation from the latest optimizer run.
- **Settings** — DB/API health check, manual trip-direction override
  (morning/evening, per bus), and an **admin action audit log** viewer.
- **Admin audit logging** — every create/update/delete from the console
  writes a row to `admin_audit_logs` (admin email, action type, target
  entity/id, details, timestamp).
- **Overspeed logging** — any GPS reading above the fixed **60 km/h**
  threshold is written to `overspeed_logs` and reflected on the dashboard.

### Continuous-learning scaffolding (not yet training anything)

There is no historical data yet, so nothing is being trained. What exists
now is the pipeline that will eventually feed training, built early so
data starts accumulating in the right shape:

- `backend/jobs/monthly_data_aggregation.py` — aggregates fuel logs,
  GPS-derived distance, route assignments/outcomes, route conditions,
  overspeed events, and maintenance events into `monthly_analytics_snapshots`
  (one row per school per month). Runs on a schedule, not manually.
- `backend/jobs/retrain_model.py` — a stub. Currently only logs how many
  months of snapshots exist and that there isn't enough data yet. Real
  training logic is a future step once several real months accumulate.
- Architecture goal: a real trained model should be able to plug in later
  without changing how data flows in or how the dashboard displays
  suggestions — same structured-output pattern the optimizer already uses.

## Database changes since the original guide

Two migrations, both additive (`IF NOT EXISTS`), run against the live
Supabase project:

- **`20260926_add_maintenance_and_audit_logs.sql`** — maintenance columns
  on `buses`; new `admin_audit_logs` and `overspeed_logs` tables.
- **`20260927_add_route_condition_ai_columns.sql`** — `speed_breaker_count`,
  `sharp_turn_count`, `traffic_level`, `road_quality` added directly to the
  existing `routes` table (no separate table); new
  `monthly_analytics_snapshots` table.

  Note: an earlier draft of this migration assumed a pre-existing
  `num_speed_breakers` column and tried to sync to it. That column never
  actually existed in the live database — the assumption was traced to an
  unapplied earlier migration file and a since-removed React reference.
  All code and SQL referencing `num_speed_breakers` has been removed;
  `speed_breaker_count` is the only column used anywhere.

  Also present but **intentionally unused**: `routes.traffic_index`
  (a raw numeric multiplier from an August 2026 schema draft). The route
  optimizer's scoring formula reads `traffic_level` exclusively —
  `traffic_index` is orphaned and safe to ignore or drop later.

## Row Level Security

RLS is **enabled** on every table. Policy model:

- **Public (anonymous, `anon` key — the parent/driver app, which has no
  login)**: read-only on `buses`, `routes`, `stops`, `live_location`.
- **Admins** (`user_roles.role = 'admin'`, checked via a `SECURITY DEFINER`
  helper function `is_admin()`): full read/write on everything.
- **Backend** (`service_role` key, used by `database.py` and the scheduled
  jobs): bypasses RLS entirely, as intended.
- **`user_roles`**: any authenticated user can read their own row (needed
  for the admin login screen's own role check); only admins can manage
  the table itself.

This was applied specifically because the admin console is now
publicly reachable by URL on GitHub Pages — before RLS, the public
Supabase anon key alone would have allowed direct read/write access to
every table with no login required.

## Setup

Follow the guide's original steps 1–7 for local setup, still accurate:

1. **Supabase** — create a project, run `database/schema.sql`, then both
   files under `database/migrations/` in order, enable Realtime on
   `live_location`, save your Project URL + keys.
2. **Backend** — `cd backend && pip install -r requirements.txt`, copy
   `.env.example` to `.env`, fill in Supabase (`service_role` key),
   Upstash, Firebase, and `GEMINI_API_KEY`, then `python main.py`
   (and separately `python gps_listener.py`).
3. **Flutter app (parent/driver, mobile):**
   ```
   cd flutter_app
   flutter pub get
   flutter run                              # or: flutter build apk --release
   ```
4. **Flutter admin console (web):**
   ```
   cd flutter_app
   flutter build web -t lib/main_admin.dart --base-href /findmybus-admin/
   ```
   Output lands in `flutter_app/build/web/` — this is what's deployed to
   GitHub Pages. To update the live site: rebuild with the command above,
   copy `build/web/`'s contents into the `findmybus-admin` GitHub repo,
   commit, and push — GitHub Pages redeploys automatically.
5. **Admin panel (React)** — untouched, not part of the current setup
   path; see "What's untouched" below if you need it for reference.
6. **Test without hardware** — `python backend/simulate_bus.py` against
   the local GPS listener, or Driver Mode on a real phone.

Every placeholder value still needs your real credentials — Supabase
project URL/keys, Upstash, Firebase, `GEMINI_API_KEY`, and the backend's
CORS allow-list (must include `https://gokum-m08.github.io` for the
hosted admin console to be able to call the API).

## Recent Flutter app fixes (parent/driver side)

- Bus Fleet screen crash fixed (`firstWhere(..., orElse: () => null)` type
  mismatch replaced with a type-safe loop).
- Dashboard and Settings mobile-width (375px) overflow bugs fixed
  (`Row`/`Expanded` layout corrections).
- `ListTile` ink-splash visibility warning fixed (removed background color
  from the intermediate `DecoratedBox` in the admin drawer).
- Route-stop editing no longer fails when a stop has students assigned to
  it — stops are now updated in place rather than deleted and reinserted,
  which previously violated the `students_stop_id_fkey` foreign key.

## Traccar integration (GT06 hardware path)

Unchanged from before — see prior notes. GPS hardware (Gomy LT02G, GT06
protocol) connects to a self-hosted Traccar server on an Azure VM
(`find-my-bus-ip`, static IP `172.198.58.39`), which forwards each
position to the backend over HTTP.

- **`backend/traccar_forward.py`** — `GET/POST /traccar-forward`, looks up
  the bus by `device_id`, converts knots → km/h, writes to
  `live_location`/`location_history`.
- **Device registration** — bus `RMKCET-394`
  (`09b59e09-af90-4d4f-8e2f-44047c27b065`) has `device_id` =
  `862607228002920`, matching the Traccar-registered IMEI.
- **Test command:**
  ```
  curl "https://find-my-bus-teu4.onrender.com/traccar-forward?uniqueId=862607228002920&latitude=13.107253&longitude=79.922789&speed=5&fixTime=2026-09-21T16:45:00Z"
  ```

## What's untouched from the guide / earlier work

`backend/main.py`'s core structure, `database.py`, `gps_listener.py`,
`schema.sql`'s original tables, and the entire `admin_panel/` React app are
left exactly as they were — the React admin panel is explicitly kept
untouched per project decision, not because it still needs maintaining.