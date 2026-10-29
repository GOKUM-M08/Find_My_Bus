import os
import re
import time
from typing import Optional, List, Dict, Set, Any
from fastapi import APIRouter, HTTPException, Depends, Request
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials
from pydantic import BaseModel
from jose import jwt, JWTError
from database import supabase
from routes.tracking import get_ordered_stops, get_eta, get_trip_direction

router = APIRouter()

ALGORITHM = "HS256"
ONE_YEAR_SECONDS = 365 * 24 * 60 * 60
CACHE_SECONDS = 60
MAX_FAILS_PER_IP = 8
MAX_FAILS_ALL = 50
FAIL_WINDOW_SECONDS = 15 * 60

_fails_by_ip: Dict[str, List[float]] = {}
_fails_all: List[float] = []


def normalize_phone(raw: str) -> Optional[str]:
    """Cleans phone numbers (+91..., 0..., spaces, dashes) to exactly 10 digits."""
    if not raw:
        return None
    digits = re.sub(r"\D", "", str(raw))
    if len(digits) == 12 and digits.startswith("91"):
        digits = digits[2:]
    elif len(digits) == 11 and digits.startswith("0"):
        digits = digits[1:]
    if len(digits) == 10:
        return digits
    return None


def _get_jwt_secret() -> str:
    secret = os.getenv("PARENT_JWT_SECRET")
    if not secret:
        raise HTTPException(
            status_code=500,
            detail="Server authentication secret (PARENT_JWT_SECRET) is not configured.",
        )
    return secret


def _create_token(phone: str) -> str:
    secret = _get_jwt_secret()
    now = int(time.time())
    payload = {
        "sub": phone,
        "phone": phone,
        "type": "parent",
        "role": "parent",
        "iat": now,
        "exp": now + ONE_YEAR_SECONDS,
    }
    return jwt.encode(payload, secret, algorithm=ALGORITHM)


def _read_token(token: str) -> Optional[str]:
    if not token:
        return None
    try:
        secret = _get_jwt_secret()
        payload = jwt.decode(
            token,
            secret,
            algorithms=[ALGORITHM],
            options={"verify_aud": False, "verify_exp": True},
        )
        if payload.get("type") != "parent" and payload.get("role") != "parent":
            return None
        return payload.get("phone") or payload.get("sub")
    except HTTPException:
        raise
    except JWTError:
        return None
    except Exception:
        return None


def _recent(timestamps: List[float], now: float) -> List[float]:
    cutoff = now - FAIL_WINDOW_SECONDS
    return [t for t in timestamps if t > cutoff]


def _client_ip(request: Request) -> str:
    forwarded = request.headers.get("x-forwarded-for")
    if forwarded:
        return forwarded.split(",")[0].strip()
    return request.client.host if request.client else "127.0.0.1"


def _check_not_blocked(ip: str) -> None:
    now = time.time()
    _fails_by_ip[ip] = _recent(_fails_by_ip.get(ip, []), now)
    _fails_all[:] = _recent(_fails_all, now)
    if len(_fails_by_ip[ip]) >= MAX_FAILS_PER_IP or len(_fails_all) >= MAX_FAILS_ALL:
        raise HTTPException(
            status_code=429,
            detail="Too many wrong attempts. Please try again after 15 minutes.",
        )


def _record_failure(ip: str) -> None:
    now = time.time()
    _fails_by_ip.setdefault(ip, []).append(now)
    _fails_all.append(now)
    if len(_fails_by_ip) > 5000:
        for key in [k for k, v in list(_fails_by_ip.items()) if not _recent(v, now)]:
            del _fails_by_ip[key]


# ─── Finding the parent's students ─────────────────────────────────

_cache: dict = {}  # phone -> (time, rows)

_STUDENT_SELECT = (
    "id, student_name, parent_name, bus_id, stop_id, school_id, "
    "buses(id, bus_number, bus_code, driver_name), "
    "stops(id, stop_name, expected_time), "
    "schools(name, phone)"
)


def _find_students(phone: str, use_cache: bool = True) -> list:
    now = time.time()
    if use_cache:
        hit = _cache.get(phone)
        if hit and now - hit[0] < CACHE_SECONDS:
            return hit[1]

    if supabase is None:
        raise HTTPException(status_code=500, detail="Database is not connected.")

    # phone is digits only (cleaned above), so it is safe inside the filter
    result = (
        supabase.table("students")
        .select(_STUDENT_SELECT)
        .or_(f"parent_phone.eq.{phone},parent_phone_2.eq.{phone}")
        .execute()
    )
    rows = result.data or []
    _cache[phone] = (now, rows)
    return rows


def _profile(phone: str, rows: list) -> dict:
    """The real profile data the app shows (no fake values)."""
    students = []
    for r in rows:
        bus = r.get("buses") or {}
        stop = r.get("stops") or {}
        school = r.get("schools") or {}
        students.append({
            "student_id": r["id"],
            "student_name": r.get("student_name"),
            "parent_name": r.get("parent_name"),
            "school_name": school.get("name"),
            "school_phone": school.get("phone"),
            "bus_id": r.get("bus_id"),
            "bus_number": bus.get("bus_number"),
            "bus_code": bus.get("bus_code"),
            "driver_name": bus.get("driver_name"),
            "stop_id": r.get("stop_id"),
            "stop_name": stop.get("stop_name"),
            "stop_expected_time": stop.get("expected_time"),
        })
    return {"phone": phone, "students": students}


# ─── "Who is calling?" check used by every parent endpoint ─────────

_bearer = HTTPBearer(auto_error=False)


def current_parent(
    creds: Optional[HTTPAuthorizationCredentials] = Depends(_bearer),
) -> dict:
    if not creds or not creds.credentials:
        raise HTTPException(status_code=401, detail="Please log in again.")
    phone = _read_token(creds.credentials)
    if phone is None:
        raise HTTPException(status_code=401, detail="Please log in again.")
    rows = _find_students(phone)
    if not rows:
        raise HTTPException(
            status_code=401,
            detail="This number is no longer registered. Please contact the school.",
        )
    return {
        "phone": phone,
        "rows": rows,
        "bus_ids": {str(r["bus_id"]) for r in rows if r.get("bus_id")},
    }


def _require_bus(parent: dict, bus_id: str) -> None:
    if str(bus_id) not in parent["bus_ids"]:
        raise HTTPException(status_code=403, detail="This bus is not linked to your account.")


def bus_ids_for_token(token: str) -> Optional[Set[str]]:
    """Used by the live WebSocket in main.py. None means 'not allowed'."""
    try:
        phone = _read_token(token or "")
    except HTTPException:
        return None
    if phone is None:
        return None
    try:
        rows = _find_students(phone)
    except Exception:
        return None
    if not rows:
        return None
    return {str(r["bus_id"]) for r in rows if r.get("bus_id")}


# ─── Endpoints ─────────────────────────────────────────────────────

class LoginBody(BaseModel):
    phone: str


@router.post("/login")
def login(body: LoginBody, request: Request):
    """Parent enters a phone number. If the school has it, return a token + profile."""
    ip = _client_ip(request)
    _check_not_blocked(ip)

    phone = normalize_phone(body.phone)
    if phone is None:
        raise HTTPException(status_code=400, detail="Please enter a valid 10-digit mobile number.")

    rows = _find_students(phone, use_cache=False)
    if not rows:
        _record_failure(ip)
        raise HTTPException(
            status_code=404,
            detail="This number is not registered with the school. Please contact the school.",
        )
    return {"token": _create_token(phone), **_profile(phone, rows)}


@router.get("/me")
def me(parent: dict = Depends(current_parent)):
    """Fresh profile. The app calls this each time it opens (it also catches stop changes)."""
    return _profile(parent["phone"], parent["rows"])


@router.get("/bus/{bus_id}/route")
def bus_route(bus_id: str, parent: dict = Depends(current_parent)):
    """Same shape as /api/buses/{bus_id}/route, but only for the parent's own bus."""
    _require_bus(parent, bus_id)
    route_res = supabase.table("routes").select("*").eq("bus_id", bus_id).execute()
    if not route_res.data:
        return []
    route = route_res.data[0]
    route["stops"] = get_ordered_stops(bus_id, route["id"])
    return [route]


@router.get("/bus/{bus_id}/live")
def bus_live(bus_id: str, parent: dict = Depends(current_parent)):
    """Latest bus position (the app polls this every few seconds)."""
    _require_bus(parent, bus_id)
    res = (
        supabase.table("live_location")
        .select("latitude, longitude, speed, timestamp")
        .eq("bus_id", bus_id)
        .limit(1)
        .execute()
    )
    return res.data[0] if res.data else None


@router.get("/bus/{bus_id}/eta/{stop_id}")
def bus_eta(bus_id: str, stop_id: str, parent: dict = Depends(current_parent)):
    _require_bus(parent, bus_id)
    return get_eta(bus_id, stop_id)


@router.get("/bus/{bus_id}/trip-direction")
def bus_trip_direction(bus_id: str, parent: dict = Depends(current_parent)):
    _require_bus(parent, bus_id)
    return get_trip_direction(bus_id)
