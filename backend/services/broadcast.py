"""
backend/services/broadcast.py

Shared broadcast and position ingest service.
Handles:
1. Saving bus position to Redis with epoch updated_at and EMA smoothed speed.
2. WebSocket location broadcasting to connected parents.
3. Triggering parent notification and progress checks directly in-process.
"""

import time
import json
import asyncio
from typing import Dict, List, Any, Optional
from database import redis_client

# Configurable constants for speed smoothing
EMA_ALPHA = 0.2
DEFAULT_SPEED_KMH = 25.0
MIN_SPEED_KMH = 15.0
MAX_SPEED_KMH = 50.0

# Active WebSocket connections per bus: bus_id -> [WebSocket, ...]
active_connections: Dict[str, List[Any]] = {}


def register_connection(bus_id: str, websocket: Any) -> None:
    """Register an active parent WebSocket for live bus updates."""
    if bus_id not in active_connections:
        active_connections[bus_id] = []
    active_connections[bus_id].append(websocket)


def remove_connection(bus_id: str, websocket: Any) -> None:
    """Remove a disconnected parent WebSocket."""
    if bus_id in active_connections and websocket in active_connections[bus_id]:
        active_connections[bus_id].remove(websocket)


async def broadcast_location(bus_id: str, location_data: dict) -> None:
    """Send live position to all parents actively watching this bus."""
    if bus_id in active_connections:
        dead = []
        for ws in active_connections[bus_id]:
            try:
                await ws.send_text(json.dumps(location_data))
            except Exception:
                dead.append(ws)
        for ws in dead:
            remove_connection(bus_id, ws)


def get_smoothed_speed(bus_id: str) -> float:
    """Retrieve current smoothed speed (EMA) from Redis, clamped [15, 50], default 25."""
    try:
        val = redis_client.get(f"bus:{bus_id}:ema_speed")
        if val is not None:
            speed = float(val.decode() if isinstance(val, bytes) else val)
            return max(MIN_SPEED_KMH, min(MAX_SPEED_KMH, speed))
    except Exception:
        pass
    return DEFAULT_SPEED_KMH


def save_bus_position(bus_id: str, lat: float, lon: float, speed: float) -> float:
    """
    ONE function that ALL ingest paths call to save position.
    Stores updated_at (epoch seconds) and computes exponential moving average (EMA)
    of speeds >= 5 km/h, clamped between 15 and 50 km/h (default 25).
    Returns the effective smoothed speed.
    """
    now_epoch = int(time.time())

    # Calculate EMA speed
    current_speed = float(speed or 0.0)
    smoothed_speed = DEFAULT_SPEED_KMH

    try:
        old_val = redis_client.get(f"bus:{bus_id}:ema_speed")
        old_ema = float(old_val.decode() if isinstance(old_val, bytes) else old_val) if old_val is not None else None

        if current_speed >= 5.0:
            if old_ema is not None:
                new_ema = (EMA_ALPHA * current_speed) + ((1.0 - EMA_ALPHA) * old_ema)
            else:
                new_ema = current_speed
            smoothed_speed = max(MIN_SPEED_KMH, min(MAX_SPEED_KMH, new_ema))
            redis_client.set(f"bus:{bus_id}:ema_speed", smoothed_speed, ex=10800)
        else:
            if old_ema is not None:
                smoothed_speed = max(MIN_SPEED_KMH, min(MAX_SPEED_KMH, old_ema))
            else:
                smoothed_speed = DEFAULT_SPEED_KMH
    except Exception:
        smoothed_speed = max(MIN_SPEED_KMH, min(MAX_SPEED_KMH, current_speed)) if current_speed >= 5.0 else DEFAULT_SPEED_KMH

    # Save position hash with updated_at epoch
    try:
        redis_client.hset(
            f"bus:{bus_id}",
            mapping={
                "latitude": lat,
                "longitude": lon,
                "speed": current_speed,
                "smoothed_speed": smoothed_speed,
                "updated_at": now_epoch,
            },
        )
        redis_client.expire(f"bus:{bus_id}", 10800)  # 3 hour TTL
    except Exception as e:
        print(f"[broadcast.py save_bus_position error] {e}")

    return smoothed_speed


async def process_bus_position(
    bus_id: str,
    lat: float,
    lon: float,
    speed: float,
    device_id: Optional[str] = None,
    source: str = "ingest",
) -> dict:
    """
    Process incoming GPS position:
    1. Persist to Redis (save_bus_position) with epoch updated_at & smoothed speed.
    2. Broadcast to connected WebSocket clients.
    3. Run parent proximity and notification checks directly in Python.
    """
    smoothed = save_bus_position(bus_id, lat, lon, speed)

    payload = {
        "bus_id": bus_id,
        "latitude": lat,
        "longitude": lon,
        "speed": speed,
        "smoothed_speed": smoothed,
        "updated_at": int(time.time()),
    }
    if device_id:
        payload["device_id"] = str(device_id)

    # 1. WebSocket broadcast
    await broadcast_location(bus_id, payload)

    # 2. Check and notify parents directly in Python (no self-HTTP loopback!)
    try:
        from routes.tracking import check_and_notify_parents
        await check_and_notify_parents(bus_id)
    except Exception as e:
        print(f"[process_bus_position notification error] bus {bus_id}: {e}")

    return {"status": "ok", "bus_id": bus_id, "speed": speed, "smoothed_speed": smoothed}
