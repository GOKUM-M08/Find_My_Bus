from fastapi import FastAPI, WebSocket, WebSocketDisconnect, Request
from fastapi.middleware.cors import CORSMiddleware
from routes import buses, tracking, students, schools, route_optimizer, gps, parent
import asyncio
import json
from database import redis_client
from traccar_forward import router as traccar_router

app = FastAPI(title="BusTrack API", version="1.0.0")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(buses.router, prefix="/api/buses", tags=["Buses"])
app.include_router(buses.router, prefix="/buses", tags=["Buses Direct"])
app.include_router(tracking.router, prefix="/api/tracking", tags=["Tracking"])
app.include_router(students.router, prefix="/api/students", tags=["Students"])
app.include_router(schools.router, prefix="/api/schools", tags=["Schools"])
app.include_router(route_optimizer.router, tags=["Route Optimizer"])
app.include_router(gps.router, tags=["GPS Ingest"])
app.include_router(traccar_router, tags=["Traccar Forward"])
app.include_router(parent.router, prefix="/api/parent", tags=["Parent"])

from services.broadcast import (
    active_connections,
    register_connection,
    remove_connection,
    broadcast_location,
    process_bus_position,
)

@app.get("/")
def root():
    return {"status": "BusTrack API Running"}

@app.websocket("/ws/track/{bus_id}")
async def websocket_track(websocket: WebSocket, bus_id: str):
    """
    Parents connect here to get live bus location updates.
    Every time bus sends GPS data, all connected parents get updated.
    """
    # Only a logged-in parent of THIS bus may connect: ws://.../ws/track/<bus_id>?token=<login token>
    allowed_buses = parent.bus_ids_for_token(websocket.query_params.get("token", ""))
    if not allowed_buses or bus_id not in allowed_buses:
        await websocket.close(code=4401)
        return

    await websocket.accept()
    register_connection(bus_id, websocket)

    try:
        while True:
            # Keep connection alive, send ping every 30 seconds
            await asyncio.sleep(30)
            await websocket.send_text(json.dumps({"type": "ping"}))
    except WebSocketDisconnect:
        remove_connection(bus_id, websocket)

@app.post("/internal/broadcast/{bus_id}")
async def internal_broadcast(bus_id: str, request: Request):
    """
    Called by driver app or external listener when a new GPS point arrives.
    Persists to Redis with epoch updated_at and EMA smoothed speed,
    pushes WebSocket broadcast, and runs parent notification checks.
    """
    location_data = await request.json()
    lat = float(location_data["latitude"])
    lon = float(location_data["longitude"])
    speed = float(location_data.get("speed", 0.0))
    device_id = location_data.get("device_id")

    res = await process_bus_position(
        bus_id=bus_id,
        lat=lat,
        lon=lon,
        speed=speed,
        device_id=device_id,
        source="internal_broadcast",
    )
    return {"status": "broadcast sent", **res}

if __name__ == "__main__":
    import uvicorn
    uvicorn.run("main:app", host="0.0.0.0", port=8000, reload=True)