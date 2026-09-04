"""
This script runs separately and listens for GPS device data.
AIS 140 GPS devices send data as raw TCP packets to a specific port.
This parses those packets and updates the database.
"""
import os 
INTERNAL_API_URL = os.getenv("INTERNAL_API_URL", "http://localhost:8000")
import asyncio
import json
import re
from database import supabase, redis_client
import httpx

GPS_PORT = 9000

def parse_gps_packet(raw_data: str) -> dict | None:
    """
    Parse raw GPS packet from AIS 140 device.
    Common format: device_id,lat,lon,speed,timestamp
    """
    try:
        parts = raw_data.strip().split(",")
        if len(parts) >= 4:
            return {
                "device_id": parts[0],
                "latitude": float(parts[1]),
                "longitude": float(parts[2]),
                "speed": float(parts[3]) if len(parts) > 3 else 0.0,
            }
    except Exception as e:
        print(f"Parse error: {e}, data: {raw_data}")
    return None

async def update_location(parsed: dict):
    """Save location to Supabase and Redis, notify parents via WebSocket."""
    device_id = parsed["device_id"]

    result = supabase.table("buses")\
        .select("id")\
        .eq("device_id", device_id)\
        .execute()

    if not result.data:
        print(f"Unknown device: {device_id}")
        return

    bus_id = result.data[0]["id"]

    redis_client.hset(f"bus:{bus_id}", mapping={
        "latitude": parsed["latitude"],
        "longitude": parsed["longitude"],
        "speed": parsed["speed"],
    })
    redis_client.expire(f"bus:{bus_id}", 3600)

    supabase.table("live_location").upsert({
        "bus_id": bus_id,
        "device_id": device_id,
        "latitude": parsed["latitude"],
        "longitude": parsed["longitude"],
        "speed": parsed["speed"],
    }, on_conflict="bus_id").execute()

        # 3. Update live_location table in Supabase
    from datetime import datetime, timezone
    supabase.table("live_location").upsert({
        "bus_id": bus_id,
        "device_id": device_id,
        "latitude": parsed["latitude"],
        "longitude": parsed["longitude"],
        "speed": parsed["speed"],
        "timestamp": datetime.now(timezone.utc).isoformat(),
    }, on_conflict="bus_id").execute()

    async with httpx.AsyncClient() as client:
        await client.post(
             f"{INTERNAL_API_URL}/internal/broadcast/{bus_id}",
            json=parsed
        )

    print(f"Updated: Bus {bus_id} → {parsed['latitude']}, {parsed['longitude']}")

async def handle_gps_client(reader, writer):
    """Handle incoming connection from GPS device."""
    addr = writer.get_extra_info('peername')
    print(f"GPS Device connected: {addr}")

    # TCP is a raw byte stream — multiple messages can arrive glued
    # together in one read() call, or a single message can arrive
    # split across two read() calls. Buffer everything and only
    # process complete lines (split on '\n'), keeping any leftover
    # partial line for the next read.
    buffer = ""

    try:
        while True:
            data = await reader.read(1024)
            if not data:
                break

            buffer += data.decode('utf-8', errors='ignore')

            while "\n" in buffer:
                line, buffer = buffer.split("\n", 1)
                line = line.strip()
                if not line:
                    continue
                parsed = parse_gps_packet(line)
                if parsed:
                    await update_location(parsed)
    except Exception as e:
        print(f"GPS connection error: {e}")
    finally:
        writer.close()
        print(f"GPS Device disconnected: {addr}")

async def start_gps_listener():
    """Start TCP server on port 9000 to receive GPS device data."""
    server = await asyncio.start_server(
        handle_gps_client,
        host='0.0.0.0',
        port=GPS_PORT
    )
    print(f"GPS Listener running on port {GPS_PORT}")
    async with server:
        await server.serve_forever()

if __name__ == "__main__":
    asyncio.run(start_gps_listener())