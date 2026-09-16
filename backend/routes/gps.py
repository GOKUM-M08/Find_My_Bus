"""
routes/gps.py
...
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
    # 1. Look up bus by device_id
    result = supabase.table("buses").select("id").eq("device_id", device_id).execute()

    if not result.data:
        raise HTTPException(status_code=404, detail=f"Unknown device: {device_id}")

    bus_id = result.data[0]["id"]
    now = datetime.now(timezone.utc).isoformat()

    # 2. Redis
    redis_client.hset(f"bus:{bus_id}", mapping={
        "latitude": lat,
        "longitude": lon,
        "speed": speed,
    })
    redis_client.expire(f"bus:{bus_id}", 3600)

    # 3. live_location — uses "timestamp" (correct, don't change this one)
    supabase.table("live_location").upsert({
        "bus_id": bus_id,
        "device_id": device_id,
        "latitude": lat,
        "longitude": lon,
        "speed": speed,
        "timestamp": now,
    }, on_conflict="bus_id").execute()

    # 4. location_history — uses "recorded_at", NOT "timestamp"
    supabase.table("location_history").insert({
        "bus_id": bus_id,
        "device_id": device_id,
        "latitude": lat,
        "longitude": lon,
        "speed": speed,
        "recorded_at": now,   # <-- this is the only line that changed
    }).execute()

    # 5. Notify parents
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