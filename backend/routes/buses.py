from fastapi import APIRouter, HTTPException
from database import supabase
from pydantic import BaseModel

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
    result = supabase.table("buses")\
        .select("*, routes(*)")\
        .eq("school_id", school_id)\
        .execute()
    return result.data

@router.post("/")
def create_bus(bus: BusCreate):
    """Register a new bus."""
    result = supabase.table("buses").insert(bus.dict()).execute()
    return result.data[0]

@router.post("/route")
def create_route(route_data: RouteCreate):
    """Create a route with stops for a bus."""
    # Create route
    route = supabase.table("routes").insert({
        "bus_id": route_data.bus_id,
        "school_id": route_data.school_id,
        "route_name": route_data.route_name,
    }).execute()
    
    route_id = route.data[0]["id"]
    
    # Add all stops
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
    result = supabase.table("routes")\
        .select("*, stops(*)")\
        .eq("bus_id", bus_id)\
        .order("stop_order", foreign_table="stops")\
        .execute()
    return result.data