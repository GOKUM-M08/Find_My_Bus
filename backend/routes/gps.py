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

    # 2. Persist to live_location (Supabase)
    supabase.table("live_location").upsert({
        "bus_id": bus_id,
        "device_id": device_id,
        "latitude": lat,
        "longitude": lon,
        "speed": speed,
        "timestamp": now,
    }, on_conflict="bus_id").execute()

    # 3. location_history
    supabase.table("location_history").insert({
        "bus_id": bus_id,
        "device_id": device_id,
        "latitude": lat,
        "longitude": lon,
        "speed": speed,
        "recorded_at": now,
    }).execute()

    # 4. Centralized Redis save (with updated_at & EMA speed), WebSocket broadcast, and notification checks
    from services.broadcast import process_bus_position
    await process_bus_position(
        bus_id=bus_id,
        lat=lat,
        lon=lon,
        speed=speed,
        device_id=device_id,
        source="gps_ingest",
    )

    print(f"[gps/ingest] Bus {bus_id} ({device_id}) -> {lat}, {lon}")
    return {"status": "ok", "bus_id": bus_id}