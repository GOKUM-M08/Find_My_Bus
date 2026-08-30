from fastapi import FastAPI, WebSocket, WebSocketDisconnect, Request
from fastapi.middleware.cors import CORSMiddleware
from routes import buses, tracking, students, schools, route_optimizer
import asyncio
import json

app = FastAPI(title="BusTrack API", version="1.0.0")

# Allow Flutter and React to connect
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)

# Include all route modules
app.include_router(buses.router, prefix="/api/buses", tags=["Buses"])
app.include_router(tracking.router, prefix="/api/tracking", tags=["Tracking"])
app.include_router(students.router, prefix="/api/students", tags=["Students"])
app.include_router(schools.router, prefix="/api/schools", tags=["Schools"])
app.include_router(route_optimizer.router, tags=["Route Optimizer"])

# Store active WebSocket connections
# Key: bus_id → List of connected parent WebSockets
active_connections: dict = {}

@app.get("/")
def root():
    return {"status": "BusTrack API Running"}

@app.websocket("/ws/track/{bus_id}")
async def websocket_track(websocket: WebSocket, bus_id: str):
    """
    Parents connect here to get live bus location updates.
    Every time bus sends GPS data, all connected parents get updated.
    """
    await websocket.accept()
    
    if bus_id not in active_connections:
        active_connections[bus_id] = []
    active_connections[bus_id].append(websocket)
    
    try:
        while True:
            # Keep connection alive, send ping every 30 seconds
            await asyncio.sleep(30)
            await websocket.send_text(json.dumps({"type": "ping"}))
    except WebSocketDisconnect:
        active_connections[bus_id].remove(websocket)

async def broadcast_location(bus_id: str, location_data: dict):
    """
    Called by GPS listener when new location arrives.
    Pushes to all parents watching this bus.
    """
    if bus_id in active_connections:
        dead_connections = []
        for ws in active_connections[bus_id]:
            try:
                await ws.send_text(json.dumps(location_data))
            except:
                dead_connections.append(ws)
        # Clean up dead connections
        for ws in dead_connections:
            active_connections[bus_id].remove(ws)

@app.post("/internal/broadcast/{bus_id}")
async def internal_broadcast(bus_id: str, request: Request):
    """
    Called by gps_listener.py every time a new GPS point arrives.
    Pushes the update to all parents connected via WebSocket, and
    checks whether any parent's stop is now 2 stops away (STEP 11.4).
    """
    location_data = await request.json()
    await broadcast_location(bus_id, location_data)
    await tracking.check_and_notify_parents(bus_id)
    return {"status": "broadcast sent"}

if __name__ == "__main__":
    import uvicorn
    uvicorn.run("main:app", host="0.0.0.0", port=8000, reload=True)
