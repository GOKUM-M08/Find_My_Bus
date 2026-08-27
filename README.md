# BusTrack (Find My Bus)

School bus tracking system — Flutter parent/driver app, FastAPI backend,
Supabase + Redis (Upstash) for data/caching, Firebase Cloud Messaging for
push notifications, and a React admin dashboard.

This project was assembled from `BUSTRACK_COMPLETE_GUIDE.md`. Every file
below traces back to a specific step in that guide. Where the guide only
gave a snippet, referenced a file it never wrote out, or left two pieces
that needed to be wired together, that's called out here and with a
`NOTE:` comment at the top of the file itself.

## Folder structure

```
bustrack/
├── backend/            FastAPI server
│   ├── main.py
│   ├── gps_listener.py     TCP listener for AIS 140 GPS devices
│   ├── database.py         Supabase + Redis clients
│   ├── notifications.py    Firebase push notification sender
│   ├── models.py
│   ├── auth.py
│   ├── simulate_bus.py     Test script — simulates a bus without hardware
│   ├── requirements.txt
│   ├── .env.example
│   └── routes/
│       ├── buses.py
│       ├── tracking.py     live location + history + ETA (STEP 11)
│       ├── students.py
│       └── schools.py
├── flutter_app/        Parent, driver & admin mobile app
│   ├── pubspec.yaml
│   ├── android/app/src/main/AndroidManifest.xml
│   └── lib/
│       ├── main.dart
│       ├── screens/
│       │   ├── login_screen.dart
│       │   ├── home_screen.dart          role-based routing (STEP 9)
│       │   ├── tracking_screen.dart      live map + ETA (STEP 11)
│       │   ├── driver_screen.dart        phone-as-GPS-tracker (STEP 5)
│       │   └── register_student_screen.dart
│       ├── services/
│       │   ├── supabase_service.dart
│       │   └── notification_service.dart
│       └── models/
│           ├── bus_model.dart
│           └── stop_model.dart
├── admin_panel/         React school admin dashboard
│   ├── package.json
│   ├── public/index.html
│   └── src/
│       ├── App.jsx
│       ├── index.js
│       ├── supabaseClient.js
│       └── components/
│           ├── BusMap.jsx
│           ├── AddBus.jsx
│           ├── RouteBuilder.jsx
│           └── StudentList.jsx
└── database/
    └── schema.sql        all Supabase tables, including user_roles (STEP 9.1)
```

## Setup

Follow the guide's steps 1–7 in order:

1. **Supabase** — create a project, run `database/schema.sql` in the SQL Editor,
   enable Realtime on `live_location`, save your Project URL + keys.
2. **Backend** — `cd backend && pip install -r requirements.txt`, copy
   `.env.example` to `.env` and fill in your real Supabase/Upstash/Firebase
   values, then `python main.py` (and separately `python gps_listener.py`).
3. **Flutter app** — `cd flutter_app && flutter create .` (to generate the
   native iOS/Android scaffolding this guide doesn't include), then drop in
   your Supabase URL/anon key in `lib/main.dart`, `flutter pub get`, run.
4. **Admin panel** — `cd admin_panel && npm install && npm start`, fill in
   your Supabase URL/anon key + Google Maps API key.
5. **Test without hardware** — run `python backend/simulate_bus.py` against
   your local GPS listener, or use Driver Mode on a real phone (STEP 5).

Every placeholder value (`yourproject.supabase.co`, `your_anon_key`,
`your-backend.onrender.com`, etc.) needs to be replaced with your real ones —
they're left as-is exactly as the guide wrote them.

## Gaps the guide left, filled in here

The guide's folder structure and cross-references implied more than its
walkthrough text actually wrote out. To make the project buildable, these
were added (each has a `NOTE:` comment at the top of the file explaining
this same thing):

- **`backend/routes/students.py`, `backend/routes/schools.py`** — listed in
  the folder structure and imported by `main.py`, but never written out.
  Basic CRUD matching the schema and the style of `routes/buses.py`.
- **`backend/models.py`, `backend/auth.py`** — listed in the folder
  structure but nothing in the guide imports from them (each route file
  defines its own inline Pydantic models; auth is handled entirely via
  Supabase on the Flutter client). Left as stubs/starting points.
- **`backend/notifications.py`** — STEP 6.3's "Send Notification from
  Backend" snippet said "add to your FastAPI backend" without a target
  file. Pulled into its own module since `routes/tracking.py`'s STEP 11.4
  notifier needs to import `send_bus_notification` from somewhere.
- **`main.py`'s `/internal/broadcast/{bus_id}` endpoint** — `gps_listener.py`
  POSTs to this URL, but the guide's `main.py` never defines it, so the
  WebSocket push to parents and the STEP 11.4 notification check would
  silently never fire. Added it, wired to both `broadcast_location()` and
  `tracking.check_and_notify_parents()`.
- **`flutter_app/lib/screens/tracking_screen.dart`** — STEP 11.3 said "add
  this to your tracking_screen.dart" as a loose snippet. Integrated it
  directly: added an optional `stopId` param, a 30-second refresh timer,
  and a "Stops Away" tile. `home_screen.dart` was updated to pass
  `stopId: userData['stop_id']` through when navigating to this screen.
- **`flutter_app/lib/services/supabase_service.dart`, `lib/models/bus_model.dart`,
  `lib/models/stop_model.dart`** — listed in the folder structure, but
  every screen in the guide talks to Supabase directly with raw
  `Map<String, dynamic>` instead. Stubs provided as a starting point.
- **`flutter_app/android/app/src/main/AndroidManifest.xml`** — STEP 5.2
  only gave four `<uses-permission>` lines to add to an existing manifest.
  Since no `flutter create` was run, a full standard manifest with those
  permissions included is provided; run `flutter create .` in
  `flutter_app/` to fill in the rest of the native project scaffolding.
- **`admin_panel/src/components/RouteBuilder.jsx`** — imported by `App.jsx`
  and shown as a "Build Route" tab, but never implemented anywhere in the
  guide. Written to POST to the `/api/buses/route` endpoint that
  `backend/routes/buses.py` already defines.
- **`admin_panel/package.json`, `public/index.html`, `src/index.js`** — the
  guide only gives the `npx create-react-app` command, not these files
  directly. Standard Create React App boilerplate.

## What's untouched from the guide

Everything else — `main.py`, `database.py`, `gps_listener.py`,
`routes/buses.py`, all of the Flutter screens, `App.jsx`, `BusMap.jsx`,
`AddBus.jsx`, `StudentList.jsx`, `schema.sql` — is copied over exactly as
written in the guide, including its placeholder URLs/keys and the known
rough edges the guide itself didn't resolve (e.g. `database.py` reads
`UPSTASH_REDIS_HOST`/`UPSTASH_REDIS_PORT` env vars that aren't listed in
the `.env` example — add those alongside `UPSTASH_REDIS_URL`/`_TOKEN` when
you fill in your real Upstash credentials).
