import math
from fastapi import APIRouter
from database import supabase, redis_client
from notifications import send_bus_notification

router = APIRouter()

@router.get("/{bus_id}/live")
def get_live_location(bus_id: str):
    """
    Get current live location of a bus.
    First checks Redis (ultra-fast), falls back to Supabase.
    """
    # Try Redis first (fastest)
    cached = redis_client.hgetall(f"bus:{bus_id}")
    if cached:
        return {
            "bus_id": bus_id,
            "latitude": float(cached.get("latitude", 0)),
            "longitude": float(cached.get("longitude", 0)),
            "speed": float(cached.get("speed", 0)),
            "source": "cache"
        }
    
    # Fallback to Supabase
    result = supabase.table("live_location")\
        .select("*")\
        .eq("bus_id", bus_id)\
        .execute()
    
    if result.data:
        return {**result.data[0], "source": "database"}
    return {"message": "No location data yet"}

@router.get("/{bus_id}/history")
def get_location_history(bus_id: str, limit: int = 100):
    """Get last N location points to draw trail on map."""
    result = supabase.table("location_history")\
        .select("latitude, longitude, speed, recorded_at")\
        .eq("bus_id", bus_id)\
        .order("recorded_at", desc=True)\
        .limit(limit)\
        .execute()
    return result.data

@router.get("/school/{school_id}/all")
def get_all_buses_location(school_id: str):
    """Get live location of ALL buses for a school (admin view)."""
    buses = supabase.table("buses")\
        .select("id, bus_number, bus_code")\
        .eq("school_id", school_id)\
        .execute()
    
    locations = []
    for bus in buses.data:
        cached = redis_client.hgetall(f"bus:{bus['id']}")
        if cached:
            locations.append({
                "bus_id": bus["id"],
                "bus_number": bus["bus_number"],
                "latitude": float(cached.get("latitude", 0)),
                "longitude": float(cached.get("longitude", 0)),
                "speed": float(cached.get("speed", 0)),
            })
    return locations


# ─── STEP 11 — ETA CALCULATION ─────────────────────────────────────

def haversine_distance(lat1: float, lon1: float,
                        lat2: float, lon2: float) -> float:
    """Calculate distance in km between two GPS coordinates."""
    R = 6371  # Earth radius in km
    dlat = math.radians(lat2 - lat1)
    dlon = math.radians(lon2 - lon1)
    a = (math.sin(dlat / 2) ** 2 +
         math.cos(math.radians(lat1)) *
         math.cos(math.radians(lat2)) *
         math.sin(dlon / 2) ** 2)
    return R * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a))

@router.get("/{bus_id}/eta/{stop_id}")
def get_eta(bus_id: str, stop_id: str):
    """
    Calculate ETA for a bus to reach a specific stop.
    Called by parent app to show arrival time.
    """
    # 1. Get live bus location from Redis
    cached = redis_client.hgetall(f"bus:{bus_id}")
    if not cached:
        return {"eta": "Location not available", "stops_away": -1}

    bus_lat = float(cached.get("latitude", 0))
    bus_lon = float(cached.get("longitude", 0))
    bus_speed = float(cached.get("speed", 20))  # default 20 km/h

    # 2. Get all stops for this bus route in order
    route = supabase.table("routes")\
        .select("id")\
        .eq("bus_id", bus_id)\
        .execute()

    if not route.data:
        return {"eta": "Route not found", "stops_away": -1}

    route_id = route.data[0]["id"]
    stops = supabase.table("stops")\
        .select("*")\
        .eq("route_id", route_id)\
        .order("stop_order")\
        .execute().data

    # 3. Find which stop the bus is nearest to right now
    nearest_stop_index = 0
    min_distance = float('inf')

    for i, stop in enumerate(stops):
        dist = haversine_distance(
            bus_lat, bus_lon,
            stop["latitude"], stop["longitude"]
        )
        if dist < min_distance:
            min_distance = dist
            nearest_stop_index = i

    # 4. Find target stop index
    target_index = next(
        (i for i, s in enumerate(stops) if s["id"] == stop_id),
        -1
    )

    if target_index == -1:
        return {"eta": "Stop not found", "stops_away": -1}

    # 5. Calculate stops remaining and distance
    if target_index <= nearest_stop_index:
        return {
            "eta": "Bus has passed your stop",
            "stops_away": 0,
            "minutes": 0
        }

    stops_away = target_index - nearest_stop_index

    # Calculate direct distance from bus to target stop
    target_stop = stops[target_index]
    total_distance_km = haversine_distance(
        bus_lat, bus_lon,
        target_stop["latitude"],
        target_stop["longitude"]
    )

    # Use actual speed if available, otherwise assume 20 km/h
    effective_speed = max(bus_speed, 10)  # min 10 km/h
    minutes = round((total_distance_km / effective_speed) * 60)

    return {
        "bus_id": bus_id,
        "stop_id": stop_id,
        "stops_away": stops_away,
        "distance_km": round(total_distance_km, 2),
        "minutes": minutes,
        "eta": f"{minutes} min" if minutes > 0 else "Arriving now",
        "bus_speed_kmh": round(effective_speed, 1)
    }


# ─── STEP 11.4 — Notify parents when bus is 2 stops away ───────────

async def check_and_notify_parents(bus_id: str):
    """
    After every GPS update, check if any parent's stop
    is 2 stops away and send them a push notification.
    Call this from gps_listener.py's update_location() after
    each new GPS point is saved.
    """
    # Get all students on this bus
    students = supabase.table("students")\
        .select("id, student_name, stop_id, fcm_token")\
        .eq("bus_id", bus_id)\
        .execute().data

    for student in students:
        if not student.get("fcm_token") or not student.get("stop_id"):
            continue

        # Get ETA for this student's stop
        eta_data = get_eta(bus_id, student["stop_id"])

        # If bus is exactly 2 stops away — notify
        if eta_data.get("stops_away") == 2:
            send_bus_notification(
                fcm_token=student["fcm_token"],
                bus_number="Your Bus",
                message=f"Bus is 2 stops away! "
                        f"Arriving in ~{eta_data['minutes']} minutes."
            )
