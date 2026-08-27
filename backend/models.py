"""
Shared data models.

NOTE: the guide's folder structure lists this file ("# Data models")
but every routes/*.py module in the guide defines its own Pydantic
models inline (BusCreate, RouteCreate, StudentCreate, etc.) instead of
importing from here. Nothing in the guide actually imports from
models.py, so this file is a stub — a natural place to consolidate
those inline models if you want one shared source of truth later.
"""
from pydantic import BaseModel
from typing import Optional


class Stop(BaseModel):
    stop_name: str
    latitude: float
    longitude: float
    stop_order: int
    expected_time: Optional[str] = None


class LiveLocation(BaseModel):
    bus_id: str
    device_id: Optional[str] = None
    latitude: float
    longitude: float
    speed: float = 0.0
