"""
traccar_forward.py

Receives position forwards from Traccar (running on the Azure VM) and
writes them into Supabase, then triggers the existing broadcast pipeline
in main.py (WebSocket push + parent stop-proximity checks).

Traccar is configured (via traccar.xml, forward.url) to substitute
placeholders directly into a GET request's query string on every new
GPS fix -- this is Traccar's built-in, well-documented forwarding
method (see PositionForwarderUrl.java) and is more reliable than its
JSON forwarding, which doesn't consistently include the device's
uniqueId (IMEI).

traccar.xml will be configured with something like:

    <entry key='forward.enable'>true</entry>
    <entry key='forward.url'>https://find-my-bus-teu4.onrender.com/traccar-forward?uniqueId={uniqueId}&amp;latitude={latitude}&amp;longitude={longitude}&amp;speed={speed}&amp;fixTime={fixTime}</entry>

Add to main.py, AFTER `app = FastAPI(...)` is created:

    from traccar_forward import router as traccar_router
    app.include_router(traccar_router, tags=["Traccar Forward"])

GET /traccar-forward is the real path Traccar hits.
POST /traccar-forward is kept as a convenience for manual testing
(e.g. curl with a JSON body) before the real tracker is outdoors.
"""

from fastapi import APIRouter, Request, HTTPException
import httpx
from datetime import datetime, timezone
from database import supabase

router = APIRouter()

# Internal broadcast endpoint lives in main.py, on the same running instance.
INTERNAL_BROADCAST_URL = "http://127.0.0.1:8000/internal/broadcast/{bus_id}"


async def _handle_position(unique_id, latitude, longitude, speed_raw, speed_unit: str = "knots"):
    """
    Shared logic: match device -> write Supabase -> trigger broadcast.
    speed_unit: "knots" (Traccar's default GET forwarding unit) or "kmh" (manual test convenience).
    """
    if unique_id is None or latitude is None or longitude is None:
        return {"status": "ignored", "reason": "missing required fields"}

    try:
        speed_val = float(speed_raw) if speed_raw is not None else 0.0
    except (TypeError, ValueError):
        speed_val = 0.0

    speed_kmh = speed_val * 1.852 if speed_unit == "knots" else speed_val

    if supabase is None:
        raise HTTPException(status_code=500, detail="Supabase client not configured")

    # Match the tracker's IMEI to a bus via buses.device_id
    bus_result = (
        supabase.table("buses")
        .select("id, bus_number")
        .eq("device_id", str(unique_id))
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
            "device_id": str(unique_id),
            "latitude": float(latitude),
            "longitude": float(longitude),
            "speed": speed_kmh,
            "timestamp": now,
        },
        on_conflict="bus_id",
    ).execute()

    # Append to history trail
    supabase.table("location_history").insert(
        {
            "bus_id": bus_id,
            "latitude": float(latitude),
            "longitude": float(longitude),
            "speed": speed_kmh,
            "recorded_at": now,
        }
    ).execute()

    # Reuse the existing broadcast pipeline (Redis cache, WebSocket push, parent notifications)
    async with httpx.AsyncClient() as client:
        try:
            await client.post(
                INTERNAL_BROADCAST_URL.format(bus_id=bus_id),
                json={"latitude": float(latitude), "longitude": float(longitude), "speed": speed_kmh},
                timeout=5,
            )
        except httpx.HTTPError as e:
            print(f"[traccar_forward] internal broadcast failed: {e}")

    return {"status": "ok", "bus_id": bus_id, "bus_number": bus.get("bus_number")}


@router.get("/traccar-forward")
async def traccar_forward_get(
    uniqueId: str = None,
    latitude: float = None,
    longitude: float = None,
    speed: float = None,
    fixTime: str = None,
):
    """
    Real endpoint Traccar hits -- placeholders substituted into the query string.
    Speed arrives in knots (Traccar's raw Position.speed unit).
    """
    return await _handle_position(uniqueId, latitude, longitude, speed, speed_unit="knots")


@router.post("/traccar-forward")
async def traccar_forward_post(request: Request):
    """
    Manual-testing convenience -- e.g.:
    curl -X POST https://<render-url>/traccar-forward \
      -H "Content-Type: application/json" \
      -d '{"uniqueId": "862607228002920", "latitude": 13.322, "longitude": 80.151, "speed": 5}'

    Speed here is treated as already km/h, since it's a human typing the test value.
    """
    payload = await request.json()
    return await _handle_position(
        payload.get("uniqueId"),
        payload.get("latitude"),
        payload.get("longitude"),
        payload.get("speed", 0),
        speed_unit="kmh",
    )
