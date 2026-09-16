"""
routes/gps.py

Replaces gps_listener.py's TCP-on-port-9000 approach.

Render Web Services only route HTTPS/443 traffic to the public internet —
raw TCP sockets (like the old asyncio.start_server on :9000) are never
reachable from outside Render. Since the SIM800L already proved it can do
AT+HTTPACTION successfully (tested against httpbin.org, got HTTP 200),
the tracker reports over HTTP GET instead of opening a TCP connection.

ESP32/SIM800L calls:
    GET /gps/ingest?device_id=394&lat=13.107253&lon=79.922789&speed=0.15

This does exactly what gps_listener.py's update_location() did:
  1. Look up the bus by device_id
  2. Write current position to Redis (fast read path for get_eta())
  3. Upsert into live_location (single write — the old code duplicated this)
  4. Insert into location_history for the trail/log
  5. Notify parents — called directly as a function now, instead of
     looping back out over HTTP to /internal/broadcast/{bus_id}, since
     this route already runs inside the same FastAPI process.
"""
from datetime import datetime, timezone
from fastapi import APIRouter, HTTPException, Query
from database import supabase, redis_client

router = APIRouter()


@router.get("/gps/ingest")
async def gps_ingest(
    device_id: str = Query(...),
    lat: float = Query(...),
    lon: float = Query(...),
    speed: float = Query(0.0),
):
    # 1. Look up bus by device_id (same lookup as gps_listener.py)
    result = supabase.table("buses").select("id").eq("device_id", device_id).execute()

    if not result.data:
        # Matches gps_listener.py's behavior, but as an HTTP error so the
        # ESP32 can see AT+HTTPACTION return a non-200 and could retry/log.
        raise HTTPException(status_code=404, detail=f"Unknown device: {device_id}")

    bus_id = result.data[0]["id"]
    now = datetime.now(timezone.utc).isoformat()

    # 2. Redis — fast path for get_eta() (unchanged from gps_listener.py)
    redis_client.hset(f"bus:{bus_id}", mapping={
        "latitude": lat,
        "longitude": lon,
        "speed": speed,
    })
    redis_client.expire(f"bus:{bus_id}", 3600)

    # 3. live_location — single upsert (the old file did this twice; collapsed here)
    supabase.table("live_location").upsert({
        "bus_id": bus_id,
        "device_id": device_id,
        "latitude": lat,
        "longitude": lon,
        "speed": speed,
        "timestamp": now,
    }, on_conflict="bus_id").execute()

    # 4. location_history — trail log (was mentioned in your architecture
    #    summary as something the driver-app path writes; kept here for parity)
    supabase.table("location_history").insert({
        "bus_id": bus_id,
        "device_id": device_id,
        "latitude": lat,
        "longitude": lon,
        "speed": speed,
        "timestamp": now,
    }).execute()

    # 5. Notify parents — direct in-process call, not an HTTP round-trip.
    # Import here (not top-level) to avoid a circular import with main.py,
    # since main.py also imports this router.
    from main import broadcast_location, active_connections
    from routes import tracking

    location_data = {
        "bus_id": bus_id,
        "device_id": device_id,
        "latitude": lat,
        "longitude": lon,
        "speed": speed,
        "timestamp": now,
    }
    await broadcast_location(bus_id, location_data)
    await tracking.check_and_notify_parents(bus_id)

    print(f"[gps/ingest] Bus {bus_id} ({device_id}) -> {lat}, {lon}")
    return {"status": "ok", "bus_id": bus_id}
