from fastapi import APIRouter
from database import supabase, redis_client
from pydantic import BaseModel
from typing import Optional
from routes.tracking import haversine_distance, get_eta

router = APIRouter()

class BusCreate(BaseModel):
    school_id: str
    bus_number: str
    bus_code: str
    driver_name: str
    driver_phone: str
    device_id: str
    capacity: int = 40

class RouteCreate(BaseModel):
    bus_id: str
    school_id: str
    route_name: str
    stops: list  # List of stop objects

@router.get("/")
def get_all_buses(school_id: str):
    """Get all buses for a school."""
    try:
        if not supabase: return []
        result = supabase.table("buses")\
            .select("*, routes(*)")\
            .eq("school_id", school_id)\
            .execute()
        return result.data
    except Exception:
        return []

@router.post("/")
def create_bus(bus: BusCreate):
    """Register a new bus."""
    if not supabase: return {"id": "dummy"}
    result = supabase.table("buses").insert(bus.dict()).execute()
    return result.data[0]

@router.post("/route")
def create_route(route_data: RouteCreate):
    """Create a route with stops for a bus."""
    if not supabase: return {"message": "Route created", "route_id": "dummy"}
    route = supabase.table("routes").insert({
        "bus_id": route_data.bus_id,
        "school_id": route_data.school_id,
        "route_name": route_data.route_name,
    }).execute()
    
    route_id = route.data[0]["id"]
    
    stops_to_insert = [
        {
            "route_id": route_id,
            "stop_name": stop["stop_name"],
            "latitude": stop["latitude"],
            "longitude": stop["longitude"],
            "stop_order": idx + 1,
            "expected_time": stop.get("expected_time", ""),
        }
        for idx, stop in enumerate(route_data.stops)
    ]
    
    supabase.table("stops").insert(stops_to_insert).execute()
    return {"message": "Route created", "route_id": route_id}

@router.get("/{bus_id}/route")
def get_bus_route(bus_id: str):
    """Get route and all stops for a specific bus."""
    try:
        if not supabase: return []
        result = supabase.table("routes")\
            .select("*, stops(*)")\
            .eq("bus_id", bus_id)\
            .order("stop_order", foreign_table="stops")\
            .execute()
        return result.data
    except Exception:
        return []


# ─── VOICE ASSISTANT ENDPOINTS ──────────────────────────────────────────

def _get_bus_coordinates(bus_id: str):
    """Helper to retrieve bus coordinates from Redis cache or live_location DB fallback."""
    try:
        cached = redis_client.hgetall(f"bus:{bus_id}")
        if cached and cached.get("latitude") and cached.get("longitude"):
            return float(cached.get("latitude", 0)), float(cached.get("longitude", 0))
    except Exception:
        pass

    try:
        if supabase:
            result = supabase.table("live_location").select("latitude, longitude").eq("bus_id", bus_id).execute()
            if result.data and len(result.data) > 0:
                loc = result.data[0]
                return float(loc.get("latitude", 0)), float(loc.get("longitude", 0))
    except Exception:
        pass
    
    return None, None


@router.get("/{bus_id}/location")
def get_bus_location_summary(bus_id: str):
    """Returns the nearest stop name to the bus's current position, for voice assistant 'where is the bus' queries."""
    lat, lon = _get_bus_coordinates(bus_id)
    if lat is None or lon is None:
        return {"nearest_landmark": "location not available", "distance_km": 0.0}

    try:
        if not supabase:
            return {"nearest_landmark": "location not available", "distance_km": 0.0}

        route = supabase.table("routes").select("id").eq("bus_id", bus_id).execute()
        if not route.data:
            return {"nearest_landmark": "route not found", "distance_km": 0.0}
        
        route_id = route.data[0]["id"]
        stops = supabase.table("stops").select("*").eq("route_id", route_id).order("stop_order").execute().data

        if not stops:
            return {"nearest_landmark": "unknown location", "distance_km": 0.0}

        nearest_stop = None
        min_distance = float('inf')
        for stop in stops:
            dist = haversine_distance(lat, lon, float(stop["latitude"]), float(stop["longitude"]))
            if dist < min_distance:
                min_distance = dist
                nearest_stop = stop

        landmark = nearest_stop["stop_name"] if nearest_stop else "unknown location"
        return {"nearest_landmark": landmark, "distance_km": round(min_distance, 2)}
    except Exception:
        return {"nearest_landmark": "location not available", "distance_km": 0.0}


@router.get("/{bus_id}/eta")
def get_eta_default(bus_id: str, stop_id: Optional[str] = None):
    """
    Voice-assistant-friendly ETA endpoint. If stop_id isn't provided,
    defaults to the bus's next upcoming stop on the route.
    """
    try:
        if not supabase:
            return {"eta_minutes": 0, "eta": "Location not available", "stops_away": -1}

        route = supabase.table("routes").select("id").eq("bus_id", bus_id).execute()
        if not route.data:
            return {"eta_minutes": 0, "eta": "Route not found", "stops_away": -1}
        
        route_id = route.data[0]["id"]
        stops = supabase.table("stops").select("*").eq("route_id", route_id).order("stop_order").execute().data

        if not stops:
            return {"eta_minutes": 0, "eta": "Stops not found", "stops_away": -1}

        if not stop_id or stop_id == "null":
            lat, lon = _get_bus_coordinates(bus_id)
            if lat is None or lon is None:
                return {"eta_minutes": 0, "eta": "Location not available", "stops_away": -1}

            nearest_index = 0
            min_distance = float('inf')
            for i, stop in enumerate(stops):
                dist = haversine_distance(lat, lon, float(stop["latitude"]), float(stop["longitude"]))
                if dist < min_distance:
                    min_distance = dist
                    nearest_index = i
            
            target_index = min(nearest_index + 1, len(stops) - 1)
            stop_id = str(stops[target_index]["id"])

        result = get_eta(bus_id, stop_id)
        return {
            "eta_minutes": result.get("minutes", 0),
            "eta": result.get("eta", "unknown"),
            "stops_away": result.get("stops_away", -1),
        }
    except Exception:
        return {"eta_minutes": 0, "eta": "Location not available", "stops_away": -1}


@router.get("/{bus_id}/status")
def get_bus_status(bus_id: str, stop_id: Optional[str] = None):
    """Is the bus running late relative to the target stop's expected arrival time."""
    try:
        eta_data = get_eta_default(bus_id, stop_id)
        minutes = eta_data.get("eta_minutes", 0)
        is_late = minutes > 10
        return {"is_late": is_late, "delay_minutes": max(0, minutes - 10) if is_late else 0}
    except Exception:
        return {"is_late": False, "delay_minutes": 0}


@router.get("/{bus_id}/stops-away")
def get_stops_away(bus_id: str, stop_id: Optional[str] = None):
    """Get number of stops away from target stop."""
    try:
        eta_data = get_eta_default(bus_id, stop_id)
        return {"stops_away": eta_data.get("stops_away", -1)}
    except Exception:
        return {"stops_away": -1}