"""Explainable, globally optimal bus-to-route recommendations."""

from __future__ import annotations

from typing import Any, Optional

import numpy as np
from fastapi import APIRouter, HTTPException, Query
from scipy.optimize import linear_sum_assignment

from database import supabase

router = APIRouter()

DEFAULT_MILEAGE_KMPL = 4.0
DEFAULT_DIESEL_PRICE_PER_L = 90.0
DEFAULT_TRAFFIC_INDEX = 1.0
FREE_FLOW_SPEED_KMPH = 40.0
DIESEL_CO2_KG_PER_L = 2.68


def _number(value: Any, default: float) -> float:
    """Return a usable positive database value, otherwise a documented default."""
    try:
        parsed = float(value)
        return parsed if parsed > 0 else default
    except (TypeError, ValueError):
        return default


def _unit_score(values: np.ndarray) -> np.ndarray:
    """Convert lower-is-better values to scores in [0, 1]."""
    low, high = float(values.min()), float(values.max())
    if np.isclose(low, high):
        return np.ones_like(values, dtype=float)
    return 1.0 - ((values - low) / (high - low))


def _capacity_fit(capacity: float, students: float) -> tuple[float, str]:
    """Prefer close fits, sharply penalising an unsafe shortage of seats."""
    if students <= 0:
        return (0.35, "No passenger data")
    if capacity < students:
        # Below 30% at a severe shortfall; never presents a shortage as a good fit.
        return (max(0.0, 0.30 * capacity / students), "Overcapacity")
    excess_ratio = (capacity - students) / students
    score = max(0.0, 1.0 - excess_ratio)
    if excess_ratio <= 0.15:
        label = "Good fit"
    elif excess_ratio <= 0.50:
        label = "Slightly oversized"
    else:
        label = "Oversized"
    return (score, label)


def _label(row: dict[str, Any], primary: str, fallback: str) -> str:
    return str(row.get(primary) or row.get(fallback) or "Unnamed")


@router.get("/admin/optimize-routes")
def optimize_routes(
    w_cost: float = Query(0.4, ge=0),
    w_time: float = Query(0.3, ge=0),
    w_capacity: float = Query(0.2, ge=0),
    w_condition: float = Query(0.1, ge=0),
    school_id: Optional[str] = Query(None, description="Optional school scope for an admin"),
):
    """Assign each available bus and route once using the Hungarian algorithm.

    Scores use min-max normalization for cost/time in this optimization run. The
    optional school_id keeps the mobile admin view from mixing schools, while the
    endpoint also works without it for a whole-fleet administrator.
    """
    weights = np.array([w_cost, w_time, w_capacity, w_condition], dtype=float)
    if float(weights.sum()) <= 0:
        raise HTTPException(422, "At least one optimization weight must be greater than zero.")
    weights /= weights.sum()

    buses_query = supabase.table("buses").select("*")
    routes_query = supabase.table("routes").select("*")
    if school_id:
        buses_query = buses_query.eq("school_id", school_id)
        routes_query = routes_query.eq("school_id", school_id)
    buses = buses_query.execute().data or []
    routes = routes_query.execute().data or []

    if not buses or not routes:
        return {
            "assignments": [],
            "matrix": [],
            "buses": [{"id": b.get("id"), "label": _label(b, "bus_number", "bus_code")} for b in buses],
            "routes": [{"id": r.get("id"), "label": _label(r, "route_name", "id")} for r in routes],
            "total_diesel_cost": 0.0,
            "total_co2_kg": 0.0,
            "unassigned_bus_count": len(buses),
            "unassigned_route_count": len(routes),
        }

    n_buses, n_routes = len(buses), len(routes)
    diesel_costs = np.zeros((n_buses, n_routes), dtype=float)
    travel_times = np.zeros((n_buses, n_routes), dtype=float)
    co2_values = np.zeros((n_buses, n_routes), dtype=float)
    capacity_scores = np.zeros((n_buses, n_routes), dtype=float)
    capacity_labels: list[list[str]] = [["" for _ in routes] for _ in buses]

    for bus_index, bus in enumerate(buses):
        mileage = _number(bus.get("mileage_kmpl"), DEFAULT_MILEAGE_KMPL)
        diesel_price = _number(bus.get("diesel_price_per_l"), DEFAULT_DIESEL_PRICE_PER_L)
        capacity = _number(bus.get("capacity"), 40.0)
        for route_index, route in enumerate(routes):
            distance = _number(route.get("distance_km"), 1.0)
            traffic = _number(route.get("traffic_index"), DEFAULT_TRAFFIC_INDEX)
            students = max(0.0, _number(route.get("student_count"), 0.0) if route.get("student_count") is not None else 0.0)
            litres = distance / mileage
            diesel_costs[bus_index, route_index] = litres * diesel_price
            co2_values[bus_index, route_index] = litres * DIESEL_CO2_KG_PER_L
            travel_times[bus_index, route_index] = (distance / FREE_FLOW_SPEED_KMPH) * traffic
            capacity_scores[bus_index, route_index], capacity_labels[bus_index][route_index] = _capacity_fit(capacity, students)

    cost_scores = _unit_score(diesel_costs)
    time_scores = _unit_score(travel_times)
    condition_scores = np.array(
        [min(1.0, max(0.0, _number(bus.get("condition_score"), 1.0))) for bus in buses],
        dtype=float,
    )[:, np.newaxis]
    suitability = (
        weights[0] * cost_scores
        + weights[1] * time_scores
        + weights[2] * capacity_scores
        + weights[3] * condition_scores
    )

    # Negating converts the maximum-score problem to scipy's minimum-cost form.
    row_indices, column_indices = linear_sum_assignment(-suitability)
    assignments = []
    for bus_index, route_index in zip(row_indices.tolist(), column_indices.tolist()):
        bus, route = buses[bus_index], routes[route_index]
        bus_label = _label(bus, "bus_number", "bus_code")
        route_label = _label(route, "route_name", "id")
        fit_label = capacity_labels[bus_index][route_index]
        explanation = (
            f"{bus_label} is the best overall match for {route_label}: it balances "
            f"diesel cost, {fit_label.lower()} capacity, travel time, and its condition."
        )
        assignments.append({
            "bus": {"id": bus.get("id"), "label": bus_label},
            "route": {"id": route.get("id"), "label": route_label},
            "score": round(float(suitability[bus_index, route_index]), 4),
            "diesel_cost": round(float(diesel_costs[bus_index, route_index]), 2),
            "travel_time_hours": round(float(travel_times[bus_index, route_index]), 2),
            "co2_kg": round(float(co2_values[bus_index, route_index]), 2),
            "capacity_fit": fit_label,
            "explanation": explanation,
        })

    return {
        "assignments": assignments,
        "matrix": [[round(float(value), 4) for value in row] for row in suitability.tolist()],
        "buses": [{"id": bus.get("id"), "label": _label(bus, "bus_number", "bus_code")} for bus in buses],
        "routes": [{"id": route.get("id"), "label": _label(route, "route_name", "id")} for route in routes],
        "total_diesel_cost": round(sum(item["diesel_cost"] for item in assignments), 2),
        "total_co2_kg": round(sum(item["co2_kg"] for item in assignments), 2),
        "unassigned_bus_count": n_buses - len(assignments),
        "unassigned_route_count": n_routes - len(assignments),
    }
