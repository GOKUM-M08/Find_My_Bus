"""Explainable, globally optimal bus-to-route recommendations with fleet analytics."""

from __future__ import annotations

from typing import Any, Optional
import numpy as np
from fastapi import APIRouter, HTTPException, Query, Body
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


def _capacity_fit(capacity: float, students: float) -> tuple[float, str, bool]:
    """Prefer close fits, penalising shortages. Returns (score, label, is_eligible)."""
    if students <= 0:
        return (0.35, "No passenger data", True)
    if capacity < students:
        # Overcapacity is ineligible
        return (max(0.0, 0.30 * capacity / students), "Overcapacity", False)
    excess_ratio = (capacity - students) / students
    score = max(0.0, 1.0 - excess_ratio)
    if excess_ratio <= 0.15:
        label = "Good fit"
    elif excess_ratio <= 0.50:
        label = "Slightly oversized"
    else:
        label = "Oversized"
    return (score, label, True)


def _compute_route_difficulty(route: dict[str, Any]) -> float | None:
    """Computes a 0-100 route difficulty score from admin-entered fields.

    Weights:
    - traffic_level (30%): low=10, medium=50, high=90
    - num_speed_breakers (25%): min(100, count * 10)
    - num_narrow_road_sections (25%): min(100, count * 25)
    - road_quality (20%): good=10, moderate=50, poor=90

    Returns None if no condition data has been manually entered by an admin.
    """
    traffic = route.get("traffic_level")
    breakers = route.get("num_speed_breakers")
    narrow = route.get("num_narrow_road_sections")
    quality = route.get("road_quality")

    # If all fields are null/unentered, return None (never guess numbers)
    if traffic is None and breakers is None and narrow is None and quality is None:
        return None

    traffic_map = {"low": 10.0, "medium": 50.0, "high": 90.0}
    quality_map = {"good": 10.0, "moderate": 50.0, "poor": 90.0}

    traffic_score = traffic_map.get(str(traffic).lower(), 30.0) if traffic else 30.0
    breaker_score = min(100.0, float(breakers) * 10.0) if breakers is not None else 0.0
    narrow_score = min(100.0, float(narrow) * 25.0) if narrow is not None else 0.0
    quality_score = quality_map.get(str(quality).lower(), 30.0) if quality else 30.0

    score = 0.30 * traffic_score + 0.25 * breaker_score + 0.25 * narrow_score + 0.20 * quality_score
    return round(float(score), 1)


def _compute_compatibility(bus: dict[str, Any], route: dict[str, Any], difficulty: float | None) -> tuple[float, str]:
    """Evaluates whether a bus is suitable for a route's physical difficulty."""
    if difficulty is None:
        return (0.80, "Neutral (Condition unentered)")

    bus_type = str(bus.get("bus_type") or "medium").lower()
    narrow_suitable = bool(bus.get("suitable_for_narrow_roads", False))
    narrow_sections = route.get("num_narrow_road_sections") or 0
    speed_breakers = route.get("num_speed_breakers") or 0
    age = bus.get("age_years") or 0

    score = 1.0
    reasons = []

    if bus_type == "large" and (narrow_sections > 0 or difficulty > 60.0):
        if not narrow_suitable:
            score -= 0.35
            reasons.append("Large vehicle on narrow/complex route")

    if speed_breakers > 5 and age > 10:
        score -= 0.15
        reasons.append("Older chassis on bumpy road")

    score = max(0.0, min(1.0, score))
    label = "; ".join(reasons) if reasons else "Fully compatible"
    return (score, label)


def _label(row: dict[str, Any], primary: str, fallback: str) -> str:
    return str(row.get(primary) or row.get(fallback) or "Unnamed")


@router.get("/admin/optimize-routes")
def optimize_routes(
    w_cost: float = Query(0.35, ge=0),
    w_time: float = Query(0.25, ge=0),
    w_capacity: float = Query(0.20, ge=0),
    w_condition: float = Query(0.10, ge=0),
    w_compatibility: float = Query(0.10, ge=0),
    school_id: Optional[str] = Query(None, description="Optional school scope for an admin"),
):
    """Assign each available bus and route once using the Hungarian algorithm."""
    weights = np.array([w_cost, w_time, w_capacity, w_condition, w_compatibility], dtype=float)
    if float(weights.sum()) <= 0:
        raise HTTPException(422, "At least one optimization weight must be greater than zero.")
    weights /= weights.sum()

    buses_query = supabase.table("buses").select("*")
    routes_query = supabase.table("routes").select("*")
    if school_id and isinstance(school_id, str):
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
            "comparison": {
                "before": {"diesel_cost": 0.0, "co2_kg": 0.0},
                "after": {"diesel_cost": 0.0, "co2_kg": 0.0},
                "improvement": {"cost_savings_pct": 0.0, "co2_reduction_pct": 0.0},
            },
        }

    n_buses, n_routes = len(buses), len(routes)
    diesel_costs = np.zeros((n_buses, n_routes), dtype=float)
    travel_times = np.zeros((n_buses, n_routes), dtype=float)
    co2_values = np.zeros((n_buses, n_routes), dtype=float)
    capacity_scores = np.zeros((n_buses, n_routes), dtype=float)
    capacity_labels: list[list[str]] = [["" for _ in routes] for _ in buses]
    eligible_matrix = np.ones((n_buses, n_routes), dtype=bool)

    route_difficulties = [_compute_route_difficulty(r) for r in routes]
    compatibility_scores = np.zeros((n_buses, n_routes), dtype=float)

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

            fit_score, fit_label, is_eligible = _capacity_fit(capacity, students)
            capacity_scores[bus_index, route_index] = fit_score
            capacity_labels[bus_index][route_index] = fit_label
            eligible_matrix[bus_index, route_index] = is_eligible

            comp_score, _ = _compute_compatibility(bus, route, route_difficulties[route_index])
            compatibility_scores[bus_index, route_index] = comp_score

    cost_scores = _unit_score(diesel_costs)
    time_scores = _unit_score(travel_times)
    condition_scores = np.array(
        [min(1.0, max(0.0, _number(bus.get("condition_score"), 1.0))) for bus in buses],
        dtype=float,
    )[:, np.newaxis]
    condition_scores_matrix = np.tile(condition_scores, (1, n_routes))

    suitability = (
        weights[0] * cost_scores
        + weights[1] * time_scores
        + weights[2] * capacity_scores
        + weights[3] * condition_scores_matrix
        + weights[4] * compatibility_scores
    )

    # Cost matrix for Hungarian algorithm:
    # Negate suitability so max suitability becomes min cost.
    # Set ineligible pairs (students > capacity) to 1e9 so they are excluded unless no eligible bus exists.
    optimization_cost_matrix = -suitability.copy()
    optimization_cost_matrix[~eligible_matrix] += 1e9

    row_indices, column_indices = linear_sum_assignment(optimization_cost_matrix)
    assignments = []

    for bus_index, route_index in zip(row_indices.tolist(), column_indices.tolist()):
        bus, route = buses[bus_index], routes[route_index]
        bus_label = _label(bus, "bus_number", "bus_code")
        route_label = _label(route, "route_name", "id")
        fit_label = capacity_labels[bus_index][route_index]
        is_eligible = bool(eligible_matrix[bus_index, route_index])

        if not is_eligible:
            explanation = (
                f"WARNING: {bus_label} is OVERCAPACITY for {route_label} "
                f"({int(route.get('student_count', 0))} students vs {int(bus.get('capacity', 0))} seats). "
                f"No fully eligible bus was available."
            )
        else:
            explanation = (
                f"{bus_label} is the optimal match for {route_label}: it balances "
                f"diesel cost, {fit_label.lower()} capacity, travel time, vehicle condition, and route compatibility."
            )

        assignments.append({
            "bus": {"id": bus.get("id"), "label": bus_label},
            "route": {"id": route.get("id"), "label": route_label},
            "score": round(float(suitability[bus_index, route_index]), 4),
            "eligible": is_eligible,
            "cost_score": round(float(cost_scores[bus_index, route_index]), 4),
            "time_score": round(float(time_scores[bus_index, route_index]), 4),
            "capacity_score": round(float(capacity_scores[bus_index, route_index]), 4),
            "condition_score": round(float(condition_scores_matrix[bus_index, route_index]), 4),
            "compatibility_score": round(float(compatibility_scores[bus_index, route_index]), 4),
            "diesel_cost": round(float(diesel_costs[bus_index, route_index]), 2),
            "travel_time_hours": round(float(travel_times[bus_index, route_index]), 2),
            "co2_kg": round(float(co2_values[bus_index, route_index]), 2),
            "capacity_fit": fit_label,
            "explanation": explanation,
        })

    # Naive baseline comparison (first bus to first route, second bus to second route)
    baseline_diesel_cost = 0.0
    baseline_co2_kg = 0.0
    for i in range(min(n_buses, n_routes)):
        baseline_diesel_cost += diesel_costs[i, i]
        baseline_co2_kg += co2_values[i, i]

    opt_diesel_cost = sum(item["diesel_cost"] for item in assignments)
    opt_co2_kg = sum(item["co2_kg"] for item in assignments)

    cost_savings_pct = (
        round(((baseline_diesel_cost - opt_diesel_cost) / baseline_diesel_cost) * 100, 2)
        if baseline_diesel_cost > 0
        else 0.0
    )
    co2_reduction_pct = (
        round(((baseline_co2_kg - opt_co2_kg) / baseline_co2_kg) * 100, 2)
        if baseline_co2_kg > 0
        else 0.0
    )

    comparison = {
        "before": {
            "diesel_cost": round(baseline_diesel_cost, 2),
            "co2_kg": round(baseline_co2_kg, 2),
        },
        "after": {
            "diesel_cost": round(opt_diesel_cost, 2),
            "co2_kg": round(opt_co2_kg, 2),
        },
        "improvement": {
            "cost_savings_pct": cost_savings_pct,
            "co2_reduction_pct": co2_reduction_pct,
            "cost_saved": round(max(0.0, baseline_diesel_cost - opt_diesel_cost), 2),
            "co2_saved": round(max(0.0, baseline_co2_kg - opt_co2_kg), 2),
        },
    }

    return {
        "assignments": assignments,
        "matrix": [[round(float(value), 4) for value in row] for row in suitability.tolist()],
        "buses": [{"id": bus.get("id"), "label": _label(bus, "bus_number", "bus_code")} for bus in buses],
        "routes": [{"id": route.get("id"), "label": _label(route, "route_name", "id")} for route in routes],
        "total_diesel_cost": round(opt_diesel_cost, 2),
        "total_co2_kg": round(opt_co2_kg, 2),
        "unassigned_bus_count": n_buses - len(assignments),
        "unassigned_route_count": n_routes - len(assignments),
        "comparison": comparison,
    }


@router.put("/admin/routes/{route_id}/condition")
def update_route_condition(route_id: str, data: dict[str, Any] = Body(...)):
    """Admin updates manually-entered route condition parameters."""
    allowed_keys = {
        "traffic_level",
        "num_speed_breakers",
        "num_narrow_road_sections",
        "road_quality",
        "avg_speed_kmph",
        "peak_congestion_window",
    }
    update_data = {k: v for k, v in data.items() if k in allowed_keys}
    if not update_data:
        raise HTTPException(400, "No valid route condition fields provided")

    result = supabase.table("routes").update(update_data).eq("id", route_id).execute()
    return {"status": "success", "data": result.data}


@router.put("/admin/buses/{bus_id}/attributes")
def update_bus_attributes(bus_id: str, data: dict[str, Any] = Body(...)):
    """Admin updates bus attributes (bus_type, age_years, suitable_for_narrow_roads)."""
    allowed_keys = {"bus_type", "age_years", "suitable_for_narrow_roads"}
    update_data = {k: v for k, v in data.items() if k in allowed_keys}
    if not update_data:
        raise HTTPException(400, "No valid bus attribute fields provided")

    result = supabase.table("buses").update(update_data).eq("id", bus_id).execute()
    return {"status": "success", "data": result.data}


# ─── PHASE 3: WHAT-IF SIMULATION & APPROVAL WORKFLOW ENDPOINTS ──────

@router.post("/admin/simulate-bus-unavailable/{bus_id}")
def simulate_bus_unavailable(bus_id: str, school_id: Optional[str] = Query(None)):
    """Re-runs optimization excluding bus_id and computes cost/time delta."""
    # 1. Run full optimization baseline
    baseline = optimize_routes(school_id=school_id)

    # 2. Exclude target bus
    buses_res = supabase.table("buses").select("*").neq("id", bus_id)
    routes_res = supabase.table("routes").select("*")
    if school_id:
        buses_res = buses_res.eq("school_id", school_id)
        routes_res = routes_res.eq("school_id", school_id)

    buses = buses_res.execute().data or []
    routes = routes_res.execute().data or []

    if not buses or not routes:
        return {"error": "Insufficient buses/routes for simulation"}

    # Target bus details
    target_bus_res = supabase.table("buses").select("*").eq("id", bus_id).execute()
    target_bus_label = _label(target_bus_res.data[0], "bus_number", "bus_code") if target_bus_res.data else bus_id

    # Compute simulation run
    sim_result = optimize_routes(school_id=school_id)

    cost_delta = round(sim_result["total_diesel_cost"] - baseline["total_diesel_cost"], 2)
    co2_delta = round(sim_result["total_co2_kg"] - baseline["total_co2_kg"], 2)

    return {
        "excluded_bus": {"id": bus_id, "label": target_bus_label},
        "baseline_diesel_cost": baseline["total_diesel_cost"],
        "simulated_diesel_cost": sim_result["total_diesel_cost"],
        "cost_delta": cost_delta,
        "co2_delta": co2_delta,
        "unassigned_route_count": sim_result["unassigned_route_count"],
        "new_assignments": sim_result["assignments"],
        "summary": (
            f"If {target_bus_label} is unavailable, diesel fuel cost changes by ₹{cost_delta:+.2f} "
            f"and unassigned routes count is {sim_result['unassigned_route_count']}."
        ),
    }
