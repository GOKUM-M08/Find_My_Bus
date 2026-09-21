"""
traccar_forward.py

Receives position forwards from Traccar (running on the Azure VM) and
writes them into Supabase, then triggers the existing broadcast pipeline
in main.py (WebSocket push + parent stop-proximity checks).

Traccar is configured (via traccar.xml) to POST here whenever a device
sends a new GPS fix. Add to main.py with:

    from traccar_forward import router as traccar_router
    app.include_router(traccar_router, tags=["Traccar Forward"])

Traccar's forwarded payload can vary slightly by version/config, so this
parses defensively and accepts any of these shapes:

  1. {"device": {"uniqueId": "..."}, "position": {"latitude": .., "longitude": .., "speed": ..}}
  2. {"uniqueId": "...", "latitude": .., "longitude": .., "speed": ..}   (flat)
  3. {"deviceId": "...", "position": {...}}   (uses deviceId as fallback identifier)
"""

from fastapi import APIRouter, Request, HTTPException
import httpx
from datetime import datetime, timezone
from database import supabase

router = APIRouter()

# Internal broadcast endpoint lives in main.py, on the same running instance.
INTERNAL_BROADCAST_URL = "http://127.0.0.1:8000/internal/broadcast/{bus_id}"


def _extract_identifier_and_position(payload: dict):
    """
    Pulls (unique_id, position_dict) out of whatever shape Traccar sent.
    Raises ValueError if required fields are missing.
    """
    device = payload.get("device") or {}
    position = payload.get("position") or payload  # flat fallback

    unique_id = (
        device.get("uniqueId")
        or payload.get("uniqueId")
        or payload.get("deviceId")  # last resort, may be Traccar's internal numeric id
    )

    latitude = position.get("latitude")
    longitude = position.get("longitude")
    speed = position.get("speed", 0)

    if unique_id is None or latitude is None or longitude is None:
        raise ValueError(f"Missing required fields in payload: {payload}")

    # Traccar reports speed in knots; convert to km/h for consistency with the rest of the app
    try:
        speed_kmh = float(speed) * 1.852
    except (TypeError, ValueError):
        speed_kmh = 0

    return str(unique_id), float(latitude), float(longitude), speed_kmh


@router.post("/traccar-forward")
async def traccar_forward(request: Request):
    payload = await request.json()

    try:
        unique_id, latitude, longitude, speed_kmh = _extract_identifier_and_position(payload)
    except ValueError as e:
        # Don't 500 on a malformed/unexpected Traccar payload — log and ack so Traccar doesn't retry-storm
        print(f"[traccar_forward] bad payload: {e}")
        return {"status": "ignored", "reason": "unparseable payload"}

    if supabase is None:
        raise HTTPException(status_code=500, detail="Supabase client not configured")

    # Match the tracker's IMEI to a bus via buses.device_id
    bus_result = (
        supabase.table("buses")
        .select("id, bus_number")
        .eq("device_id", unique_id)
        .limit(1)
        .execute()
    )

    if not bus_result.data:
        print(f"[traccar_forward] no bus found for device_id={unique_id}")
        return {"status": "ignored", "reason": "unknown device_id"}

    bus = bus_result.data[0]
    bus_id = bus["id"]

    now = datetime.now(timezone.utc).isoformat()

    # Upsert current position (one row per bus)
    supabase.table("live_location").upsert(
        {
            "bus_id": bus_id,
            "device_id": unique_id,
            "latitude": latitude,
            "longitude": longitude,
            "speed": speed_kmh,
            "timestamp": now,
        },
        on_conflict="bus_id",
    ).execute()

    # Append to history trail
    supabase.table("location_history").insert(
        {
            "bus_id": bus_id,
            "latitude": latitude,
            "longitude": longitude,
            "speed": speed_kmh,
            "recorded_at": now,
        }
    ).execute()

    # Reuse the existing broadcast pipeline (Redis cache, WebSocket push, parent notifications)
    async with httpx.AsyncClient() as client:
        try:
            await client.post(
                INTERNAL_BROADCAST_URL.format(bus_id=bus_id),
                json={"latitude": latitude, "longitude": longitude, "speed": speed_kmh},
                timeout=5,
            )
        except httpx.HTTPError as e:
            print(f"[traccar_forward] internal broadcast failed: {e}")

    return {"status": "ok", "bus_id": bus_id, "bus_number": bus.get("bus_number")}
