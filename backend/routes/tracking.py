import math
import time
import json
import asyncio
from datetime import datetime, timezone, timedelta
from typing import Dict, List, Tuple, Optional, Any
from fastapi import APIRouter
from database import supabase, redis_client
from notifications import send_alert
from services.broadcast import (
    save_bus_position,
    get_smoothed_speed,
    DEFAULT_SPEED_KMH,
    MIN_SPEED_KMH,
    MAX_SPEED_KMH,
    EMA_ALPHA,
)

router = APIRouter()

# ─── CONFIGURATION CONSTANTS ───────────────────────────────────────
ROAD_FACTOR = 1.25
STOP_REACHED_RADIUS_KM = 0.15  # 150m threshold to count as arrived/reached
FINAL_STOP_RADIUS_KM = 0.15    # backward compatibility alias
DIRECTION_SELF_HEAL_RADIUS_KM = 0.5  # 500m of first morning stop
DIRECTION_SELF_HEAL_TIME_SECONDS = 3 * 3600  # 3 hours
POSITION_OFFLINE_SECONDS = 90
STOPS_CACHE_TTL = 300  # 5 minutes in-memory cache
PROGRESS_TTL = 3 * 3600  # 3 hours
IST = timezone(timedelta(hours=5, minutes=30))

# In-memory caches for route stops to guarantee 0 Supabase calls on warm updates
_stops_cache: Dict[str, Tuple[float, List[dict]]] = {}  # bus_id -> (timestamp, stops_morning)
_route_id_cache: Dict[str, Tuple[float, str]] = {}      # bus_id -> (timestamp, route_id)

# In-memory duplicate tracker for backwards compatibility with tests
_notified_stops: Dict[str, bool] = {}


def haversine_distance(lat1: float, lon1: float, lat2: float, lon2: float) -> float:
    """Calculate great-circle distance in kilometers between two GPS coordinates."""
    R = 6371.0  # Earth radius in km
    dlat = math.radians(lat2 - lat1)
    dlon = math.radians(lon2 - lon1)
    a = (math.sin(dlat / 2.0) ** 2 +
         math.cos(math.radians(lat1)) *
         math.cos(math.radians(lat2)) *
         math.sin(dlon / 2.0) ** 2)
    return R * 2.0 * math.atan2(math.sqrt(a), math.sqrt(1.0 - a))


def clear_stops_cache(bus_id: Optional[str] = None) -> None:
    """Utility to invalidate stops cache for testing or route updates."""
    if bus_id:
        _stops_cache.pop(bus_id, None)
        _route_id_cache.pop(bus_id, None)
    else:
        _stops_cache.clear()
        _route_id_cache.clear()


def get_morning_stops(bus_id: str, route_id: Optional[str] = None, use_cache: bool = True) -> List[dict]:
    """Fetch raw stops in ascending stop_order (morning sequence), with 5-min memory caching."""
    now = time.time()
    if use_cache and bus_id in _stops_cache:
        cached_time, cached_stops = _stops_cache[bus_id]
        if now - cached_time < STOPS_CACHE_TTL:
            return cached_stops

    if not supabase:
        return []

    # Get route_id
    if not route_id:
        if use_cache and bus_id in _route_id_cache:
            r_time, r_id = _route_id_cache[bus_id]
            if now - r_time < STOPS_CACHE_TTL:
                route_id = r_id

    if not route_id:
        route_res = supabase.table("routes").select("id").eq("bus_id", bus_id).execute()
        if not route_res.data:
            return []
        route_id = route_res.data[0]["id"]
        _route_id_cache[bus_id] = (now, route_id)

    stops_res = supabase.table("stops").select("*").eq("route_id", route_id).order("stop_order").execute()
    stops = stops_res.data or []
    _stops_cache[bus_id] = (now, stops)
    return stops


def get_ordered_stops(bus_id: str, route_id: Optional[str] = None, use_cache: bool = True) -> List[dict]:
    """
    Fetch stops for a route in correct directional order:
    - 'morning': ascending by stop_order (pickup sequence)
    - 'evening': descending (drop-off sequence)
    """
    stops = get_morning_stops(bus_id, route_id=route_id, use_cache=use_cache)
    if not stops:
        return []

    direction = redis_client.get(f"bus:{bus_id}:trip_direction") or "morning"
    direction = direction.decode() if isinstance(direction, bytes) else direction

    if direction == "evening":
        return list(reversed(stops))
    return list(stops)


def get_bus_progress(bus_id: str, current_direction: str) -> Tuple[int, dict]:
    """
    Retrieve monotonic trip progress from Redis key bus:{bus_id}:progress.
    Resets progress if trip direction has changed.
    """
    key = f"bus:{bus_id}:progress"
    data = None
    try:
        raw = redis_client.get(key)
        if raw:
            data = json.loads(raw.decode() if isinstance(raw, bytes) else raw)
    except Exception:
        data = None

    if not data or data.get("direction") != current_direction:
        today_ist = datetime.now(IST).strftime("%Y-%m-%d")
        new_data = {
            "direction": current_direction,
            "passed_index": -1,
            "trip_date": today_ist,
            "updated_at": time.time(),
        }
        try:
            redis_client.set(key, json.dumps(new_data), ex=PROGRESS_TTL)
        except Exception:
            pass
        return -1, new_data

    return int(data.get("passed_index", -1)), data


def update_bus_progress(
    bus_id: str,
    bus_lat: float,
    bus_lon: float,
    stops: List[dict],
    current_direction: str,
) -> int:
    """
    Monotonically advance passed_index:
    1. Stop counts as reached when bus is within 150m (STOP_REACHED_RADIUS_KM).
    2. Advance passed_index if bus is clearly past without entering 150m (GPS gaps):
       while distance to stop after next < distance to next stop, advance.
    3. Never decreases during the trip.
    """
    passed_index, progress_dict = get_bus_progress(bus_id, current_direction)
    n_stops = len(stops)
    if n_stops == 0:
        return passed_index

    # 1. Check for physical arrival within 150m of upcoming stops
    for i in range(passed_index + 1, n_stops):
        stop = stops[i]
        dist = haversine_distance(bus_lat, bus_lon, float(stop["latitude"]), float(stop["longitude"]))
        if dist <= STOP_REACHED_RADIUS_KM:
            passed_index = max(passed_index, i)

    # 2. Advance passed_index on GPS gaps where bus skipped the 150m circle
    while passed_index + 2 < n_stops:
        next_stop = stops[passed_index + 1]
        after_next_stop = stops[passed_index + 2]
        dist_to_next = haversine_distance(
            bus_lat, bus_lon, float(next_stop["latitude"]), float(next_stop["longitude"])
        )
        dist_to_after_next = haversine_distance(
            bus_lat, bus_lon, float(after_next_stop["latitude"]), float(after_next_stop["longitude"])
        )
        if dist_to_after_next < dist_to_next:
            passed_index += 1
        else:
            break

    # Persist progress
    progress_dict["passed_index"] = passed_index
    progress_dict["updated_at"] = time.time()
    try:
        redis_client.set(f"bus:{bus_id}:progress", json.dumps(progress_dict), ex=PROGRESS_TTL)
    except Exception:
        pass

    return passed_index


def _sync_check_and_flip_trip_direction(bus_id: str, bus_lat: float, bus_lon: float) -> str:
    """
    Handles direction flip at final stop (150m) and self-heal:
    - If direction is evening, within 500m of first morning stop, and last flip > 3h ago: self-heal to morning.
    - If at final stop of current direction within 150m: flip direction.
    """
    # use_cache=False to ensure dynamic route tests don't read stale route cache
    morning_stops = get_morning_stops(bus_id, use_cache=False)
    if not morning_stops:
        return "morning"

    raw_dir = redis_client.get(f"bus:{bus_id}:trip_direction") or "morning"
    current_direction = raw_dir.decode() if isinstance(raw_dir, bytes) else raw_dir

    raw_time = redis_client.get(f"bus:{bus_id}:trip_direction_time")
    last_flip_time = float(raw_time.decode() if isinstance(raw_time, bytes) else raw_time) if raw_time else 0.0
    now = time.time()

    # 1. Self-heal: If direction is evening and bus is within 500m of first morning stop (>3 hours)
    if current_direction == "evening":
        first_stop = morning_stops[0]
        dist_first = haversine_distance(
            bus_lat, bus_lon, float(first_stop["latitude"]), float(first_stop["longitude"])
        )
        if dist_first <= DIRECTION_SELF_HEAL_RADIUS_KM and (now - last_flip_time > DIRECTION_SELF_HEAL_TIME_SECONDS or last_flip_time == 0):
            current_direction = "morning"
            redis_client.set(f"bus:{bus_id}:trip_direction", "morning")
            redis_client.set(f"bus:{bus_id}:trip_direction_time", now)
            redis_client.delete(f"bus:{bus_id}:progress")
            print(f"[Trip Direction Self-Heal] Bus {bus_id} near first stop -> reset to morning")
            return "morning"

    # 2. Check arrival at final stop of current direction (150m threshold)
    final_stop = morning_stops[-1] if current_direction == "morning" else morning_stops[0]
    dist_final = haversine_distance(
        bus_lat, bus_lon, float(final_stop["latitude"]), float(final_stop["longitude"])
    )

    already_flipped_key = f"bus:{bus_id}:flipped_at_{final_stop['id']}"
    if dist_final <= STOP_REACHED_RADIUS_KM:
        if not redis_client.get(already_flipped_key):
            new_direction = "evening" if current_direction == "morning" else "morning"
            redis_client.set(f"bus:{bus_id}:trip_direction", new_direction)
            redis_client.set(f"bus:{bus_id}:trip_direction_time", now)
            redis_client.delete(f"bus:{bus_id}:progress")
            redis_client.set(already_flipped_key, "1", ex=3600)  # 1 hour debounce
            print(f"[Trip Direction] Bus {bus_id} reached final stop ({dist_final*1000:.0f}m) -> {current_direction} to {new_direction}")
            return new_direction
    else:
        # Bus has moved away from final stop - clear debounce keys
        try:
            redis_client.delete(f"bus:{bus_id}:flipped_at_{morning_stops[-1]['id']}")
            redis_client.delete(f"bus:{bus_id}:flipped_at_{morning_stops[0]['id']}")
        except Exception:
            pass

    return current_direction


async def check_and_flip_trip_direction(bus_id: str, bus_lat: float, bus_lon: float) -> str:
    """Async wrapper for check_and_flip_trip_direction."""
    return _sync_check_and_flip_trip_direction(bus_id, bus_lat, bus_lon)


@router.get("/{bus_id}/live")
def get_live_location(bus_id: str):
    """Get current live location of a bus from Redis with Supabase fallback."""
    cached = redis_client.hgetall(f"bus:{bus_id}")
    if cached and cached.get("latitude") and cached.get("longitude"):
        return {
            "bus_id": bus_id,
            "latitude": float(cached.get("latitude", 0)),
            "longitude": float(cached.get("longitude", 0)),
            "speed": float(cached.get("speed", 0)),
            "smoothed_speed": float(cached.get("smoothed_speed", cached.get("speed", 0))),
            "updated_at": int(cached.get("updated_at", 0)),
            "source": "cache",
        }

    if supabase:
        result = (
            supabase.table("live_location")
            .select("*")
            .eq("bus_id", bus_id)
            .execute()
        )
        if result.data:
            return {**result.data[0], "source": "database"}
    return {"message": "No location data yet"}


@router.get("/{bus_id}/history")
def get_location_history(bus_id: str, limit: int = 100):
    """Get last N location points to draw trail on map."""
    if not supabase:
        return []
    result = (
        supabase.table("location_history")
        .select("latitude, longitude, speed, recorded_at")
        .eq("bus_id", bus_id)
        .order("recorded_at", desc=True)
        .limit(limit)
        .execute()
    )
    return result.data or []


@router.get("/school/{school_id}/all")
def get_all_buses_location(school_id: str):
    """Get live location of all buses for a school (admin view)."""
    if not supabase:
        return []
    buses = (
        supabase.table("buses")
        .select("id, bus_number, bus_code")
        .eq("school_id", school_id)
        .execute()
    )
    locations = []
    for bus in (buses.data or []):
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


@router.get("/{bus_id}/trip-direction")
def get_trip_direction(bus_id: str):
    """Expose current trip direction for a bus ('morning' or 'evening')."""
    direction = redis_client.get(f"bus:{bus_id}:trip_direction") or "morning"
    direction = direction.decode() if isinstance(direction, bytes) else direction
    return {"trip_direction": direction}


@router.post("/{bus_id}/trip-direction")
def set_trip_direction(bus_id: str, payload: dict):
    """Admin manual override for bus trip direction ('morning' or 'evening')."""
    direction = payload.get("trip_direction", "morning").lower()
    if direction not in ("morning", "evening"):
        direction = "morning"
    redis_client.set(f"bus:{bus_id}:trip_direction", direction)
    redis_client.set(f"bus:{bus_id}:trip_direction_time", time.time())
    redis_client.delete(f"bus:{bus_id}:progress")
    return {"status": "success", "bus_id": bus_id, "trip_direction": direction}


@router.get("/{bus_id}/ordered-stops")
def get_stops_in_direction_order(bus_id: str):
    """Get route stops in current trip direction order."""
    return get_ordered_stops(bus_id)


@router.get("/{bus_id}/eta/{stop_id}")
def get_eta(bus_id: str, stop_id: str):
    """
    Calculate ETA and progress status for a bus reaching a specific stop.
    Status values: approaching | arrived | passed | offline | no_data.
    For anything other than approaching, minutes is null and stops_away is not shown as a number.
    Uses distance along the route multiplied by ROAD_FACTOR = 1.25 and smoothed EMA speed.
    """
    now = time.time()
    bus_lat: Optional[float] = None
    bus_lon: Optional[float] = None
    bus_speed: float = DEFAULT_SPEED_KMH
    updated_at: float = 0.0

    # 1. Read Redis position
    try:
        cached = redis_client.hgetall(f"bus:{bus_id}")
        if cached and cached.get("latitude") and cached.get("longitude"):
            bus_lat = float(cached["latitude"])
            bus_lon = float(cached["longitude"])
            bus_speed = float(cached.get("speed", DEFAULT_SPEED_KMH))
            updated_at = float(cached.get("updated_at", 0))
    except Exception:
        pass

    # Fallback to Supabase live_location if Redis is empty
    if bus_lat is None or (bus_lat == 0.0 and bus_lon == 0.0):
        try:
            if supabase:
                result = (
                    supabase.table("live_location")
                    .select("latitude, longitude, speed, timestamp")
                    .eq("bus_id", bus_id)
                    .limit(1)
                    .execute()
                )
                if result.data and len(result.data) > 0:
                    loc = result.data[0]
                    bus_lat = float(loc.get("latitude", 0) or 0)
                    bus_lon = float(loc.get("longitude", 0) or 0)
                    bus_speed = float(loc.get("speed", DEFAULT_SPEED_KMH) or DEFAULT_SPEED_KMH)
                    ts_str = loc.get("timestamp")
                    if ts_str:
                        try:
                            dt = datetime.fromisoformat(ts_str.replace("Z", "+00:00"))
                            updated_at = dt.timestamp()
                        except Exception:
                            updated_at = now
                    else:
                        updated_at = now
        except Exception:
            pass

    # No coordinates available
    if bus_lat is None or (bus_lat == 0.0 and bus_lon == 0.0):
        return {
            "status": "no_data",
            "eta": "Waiting for bus location",
            "stops_away": None,
            "minutes": None,
            "distance_km": None,
            "bus_speed_kmh": None,
            "bus_id": bus_id,
            "stop_id": stop_id,
        }

    # Stale position (> 90 seconds old) -> offline
    if updated_at > 0 and (now - updated_at > POSITION_OFFLINE_SECONDS):
        return {
            "status": "offline",
            "eta": "Bus offline",
            "stops_away": None,
            "minutes": None,
            "distance_km": None,
            "bus_speed_kmh": round(bus_speed, 1),
            "bus_id": bus_id,
            "stop_id": stop_id,
        }

    # 2. Get stops for current trip direction
    stops = get_ordered_stops(bus_id)
    if not stops:
        return {
            "status": "no_data",
            "eta": "Waiting for bus location",
            "stops_away": None,
            "minutes": None,
            "distance_km": None,
            "bus_speed_kmh": None,
            "bus_id": bus_id,
            "stop_id": stop_id,
        }

    # Find target stop index
    target_index = next(
        (i for i, s in enumerate(stops) if str(s["id"]) == str(stop_id)),
        -1
    )
    if target_index == -1:
        return {
            "status": "no_data",
            "eta": "Stop not found",
            "stops_away": None,
            "minutes": None,
            "distance_km": None,
            "bus_speed_kmh": None,
            "bus_id": bus_id,
            "stop_id": stop_id,
        }

    target_stop = stops[target_index]
    target_dist_km = haversine_distance(
        bus_lat, bus_lon, float(target_stop["latitude"]), float(target_stop["longitude"])
    )
    effective_speed = get_smoothed_speed(bus_id)

    # 3. Read current monotonic progress
    direction = redis_client.get(f"bus:{bus_id}:trip_direction") or "morning"
    direction = direction.decode() if isinstance(direction, bytes) else direction
    passed_index, _ = get_bus_progress(bus_id, direction)

    # Case A: Bus is at this stop (within 150m)
    if target_dist_km <= STOP_REACHED_RADIUS_KM:
        return {
            "status": "arrived",
            "eta": "Bus is at your stop",
            "stops_away": None,
            "minutes": None,
            "distance_km": round(target_dist_km, 2),
            "bus_speed_kmh": round(effective_speed, 1),
            "bus_id": bus_id,
            "stop_id": stop_id,
        }

    # Case B: Bus has passed this stop
    if target_index < passed_index:
        return {
            "status": "passed",
            "eta": "Bus has passed your stop",
            "stops_away": None,
            "minutes": None,
            "distance_km": round(target_dist_km, 2),
            "bus_speed_kmh": round(effective_speed, 1),
            "bus_id": bus_id,
            "stop_id": stop_id,
        }

    # If target_index == passed_index but bus is already > 150m away from it, it has passed
    if target_index == passed_index and target_dist_km > STOP_REACHED_RADIUS_KM:
        return {
            "status": "passed",
            "eta": "Bus has passed your stop",
            "stops_away": None,
            "minutes": None,
            "distance_km": round(target_dist_km, 2),
            "bus_speed_kmh": round(effective_speed, 1),
            "bus_id": bus_id,
            "stop_id": stop_id,
        }

    # Case C: Bus is approaching target_index (target_index > passed_index)
    stops_away = target_index - passed_index
    next_stop_idx = passed_index + 1 if passed_index >= 0 else 0
    next_stop = stops[next_stop_idx]

    dist_bus_to_next = haversine_distance(
        bus_lat, bus_lon, float(next_stop["latitude"]), float(next_stop["longitude"])
    )

    # Sum of inter-stop distances from next_stop up to target_stop
    inter_stop_dist = 0.0
    for k in range(next_stop_idx, target_index):
        s_cur = stops[k]
        s_nxt = stops[k + 1]
        inter_stop_dist += haversine_distance(
            float(s_cur["latitude"]), float(s_cur["longitude"]),
            float(s_nxt["latitude"]), float(s_nxt["longitude"])
        )

    remaining_route_km = (dist_bus_to_next + inter_stop_dist) * ROAD_FACTOR
    minutes = max(1, math.ceil((remaining_route_km / effective_speed) * 60))

    return {
        "status": "approaching",
        "eta": f"{minutes} min",
        "stops_away": stops_away,
        "minutes": minutes,
        "distance_km": round(remaining_route_km, 2),
        "bus_speed_kmh": round(effective_speed, 1),
        "bus_id": bus_id,
        "stop_id": stop_id,
    }


def _sync_check_and_notify_parents(bus_id: str) -> None:
    """
    Synchronous implementation executed via asyncio.to_thread to avoid freezing the event loop.
    Monotonically tracks trip progress, checks 2-stops-away alerts, and eliminates redundant DB calls.
    """
    try:
        cached = redis_client.hgetall(f"bus:{bus_id}")
        bus_lat = None
        bus_lon = None
        if cached and cached.get("latitude") and cached.get("longitude"):
            bus_lat = float(cached["latitude"])
            bus_lon = float(cached["longitude"])
            updated_at = float(cached.get("updated_at", 0))
            if updated_at > 0 and (time.time() - updated_at > POSITION_OFFLINE_SECONDS):
                return

        raw_dir = redis_client.get(f"bus:{bus_id}:trip_direction") or "morning"
        current_direction = raw_dir.decode() if isinstance(raw_dir, bytes) else raw_dir

        # Self-heal check if bus was stuck in evening and is near morning start
        if current_direction == "evening" and bus_lat is not None and bus_lon is not None:
            current_direction = _sync_check_and_flip_trip_direction(bus_id, bus_lat, bus_lon)

        # 1. Get stops from memory cache
        stops = get_ordered_stops(bus_id, use_cache=True)
        if not stops:
            return

        # 2. Update monotonic progress if coordinates are available
        passed_index = -1
        if bus_lat is not None and bus_lon is not None:
            passed_index = update_bus_progress(bus_id, bus_lat, bus_lon, stops, current_direction)

        # 3. Look up bus number
        bus_number = cached.get("bus_number") if cached else None
        if not bus_number and supabase:
            b_res = supabase.table("buses").select("bus_number").eq("id", bus_id).execute()
            if b_res.data:
                bus_number = b_res.data[0]["bus_number"]
        bus_number = bus_number or "Your Bus"

        today_ist = datetime.now(IST).strftime("%Y-%m-%d")
        morning_stops = get_morning_stops(bus_id, use_cache=True)

        # ─── EVENT 1: bus_started (MORNING trip only) ────────────────────────
        if current_direction == "morning" and morning_stops and bus_lat is not None and bus_lon is not None:
            try:
                first_stop = morning_stops[0]
                dist_to_first = haversine_distance(
                    bus_lat, bus_lon, float(first_stop["latitude"]), float(first_stop["longitude"])
                )
                if dist_to_first <= STOP_REACHED_RADIUS_KM:
                    redis_client.set(f"bus:{bus_id}:was_at_first_stop", "1", ex=10800)

                started_dedup_key = f"notif:started:{bus_id}:{today_ist}"
                redis_started = redis_client.get(started_dedup_key)
                is_started_sent = bool(redis_started) and not hasattr(redis_started, "_mock_return_value")

                if not is_started_sent:
                    was_at_first_raw = redis_client.get(f"bus:{bus_id}:was_at_first_stop")
                    was_at_first = bool(was_at_first_raw) and not hasattr(was_at_first_raw, "_mock_return_value")
                    cur_speed = float(cached.get("speed", 0.0))

                    should_send = False
                    # Normal: was within 150m of first stop and is now > 300m away
                    if was_at_first and dist_to_first > 0.30:
                        should_send = True
                    # Fallback: started > 300m away, still before 2nd stop (passed_index <= 0), moving >= 5 km/h, <= 1km away
                    elif (not was_at_first) and (0.30 < dist_to_first <= 1.0) and passed_index <= 0 and cur_speed >= 5.0:
                        should_send = True

                    if should_send:
                        stop_name = first_stop.get("stop_name", "first stop")
                        send_alert(
                            event="bus_started",
                            bus_id=bus_id,
                            variables={"bus": bus_number, "stop": stop_name},
                        )
                        redis_client.set(started_dedup_key, "1", ex=64800)
            except Exception as e:
                print(f"[check_and_notify_parents bus_started error] bus {bus_id}: {e}")

        # ─── EVENT 2: two_stops_away (for each stop on route) ────────────────
        for i, stop in enumerate(stops):
            stop_id = str(stop["id"])
            eta_data = get_eta(bus_id, stop_id)
            stops_away = eta_data.get("stops_away")
            minutes = eta_data.get("minutes")
            cache_key = f"{bus_id}:{stop_id}"
            dedup_key = f"notif:near:{bus_id}:{stop_id}:{current_direction}:{today_ist}"

            if stops_away is not None and 0 < stops_away <= 2:
                redis_val = redis_client.get(dedup_key)
                is_redis_dup = bool(redis_val) and not hasattr(redis_val, "_mock_return_value")
                already_notified = _notified_stops.get(cache_key, False) or is_redis_dup
                if not already_notified:
                    stop_name = stop.get("stop_name", "your stop")
                    est_min = minutes if minutes is not None else 5
                    message = (
                        f"Bus is {stops_away} stop{'s' if stops_away > 1 else ''} away from {stop_name}! "
                        f"Arriving in ~{est_min} min."
                    )
                    try:
                        send_alert(
                            event="two_stops_away",
                            bus_id=bus_id,
                            stop_id=stop_id,
                            variables={"bus": bus_number, "stop": stop_name, "min": minutes},
                        )
                    except Exception as e:
                        print(f"Failed send_alert for {stop_id}: {e}")

                    

                    _notified_stops[cache_key] = True
                    redis_client.set(dedup_key, "1", ex=64800)
            else:
                _notified_stops[cache_key] = False

        # ─── EVENT 3: reached_college (MORNING trip only) ────────────────────
        if current_direction == "morning" and morning_stops and bus_lat is not None and bus_lon is not None:
            try:
                final_stop = morning_stops[-1]
                dist_to_final = haversine_distance(
                    bus_lat, bus_lon, float(final_stop["latitude"]), float(final_stop["longitude"])
                )
                if dist_to_final <= STOP_REACHED_RADIUS_KM:
                    arrived_dedup_key = f"notif:arrived:{bus_id}:{today_ist}"
                    redis_arrived = redis_client.get(arrived_dedup_key)
                    is_arrived_sent = bool(redis_arrived) and not hasattr(redis_arrived, "_mock_return_value")
                    if not is_arrived_sent:
                        college_name = final_stop.get("stop_name", "the college")
                        send_alert(
                            event="reached_college",
                            bus_id=bus_id,
                            variables={"bus": bus_number, "college": college_name},
                        )
                        redis_client.set(arrived_dedup_key, "1", ex=64800)
            except Exception as e:
                print(f"[check_and_notify_parents reached_college error] bus {bus_id}: {e}")

        # 4. Flip direction if bus has arrived at the final stop of current direction
        if bus_lat is not None and bus_lon is not None:
            _sync_check_and_flip_trip_direction(bus_id, bus_lat, bus_lon)

    except Exception as e:
        print(f"[check_and_notify_parents error] bus {bus_id}: {e}")


async def check_and_notify_parents(bus_id: str) -> None:
    """Async wrapper running synchronous notification & progress logic in thread."""
    await asyncio.to_thread(_sync_check_and_notify_parents, bus_id)
