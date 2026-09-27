"""Explainable, globally optimal bus-to-route recommendations with fleet analytics & Gemini LLM explanations."""

from __future__ import annotations

import os
import json
import logging
from typing import Any, Optional
import numpy as np
import requests
from fastapi import APIRouter, HTTPException, Query, Body
from scipy.optimize import linear_sum_assignment

from database import supabase

logger = logging.getLogger("uvicorn")
router = APIRouter()

DEFAULT_MILEAGE_KMPL = 4.0
DEFAULT_DIESEL_PRICE_PER_L = 90.0
FREE_FLOW_SPEED_KMPH = 40.0
DIESEL_CO2_KG_PER_L = 2.68
OPERATIONAL_DAYS_PER_MONTH = 22


def _number(value: Any, default: float) -> float:
    """Return a usable positive database value, otherwise a documented default."""
    try:
        parsed = float(value)
        return parsed if parsed > 0 else default
    except (TypeError, ValueError):
        return default


def compute_effective_distance(route: dict[str, Any]) -> float:
    """
    Exact Adjusted Effective Distance Formula (D_eff):
    D_eff = (raw_distance + (0.15 * speed_breaker_count) + (0.10 * sharp_turn_count)) * traffic_multiplier * road_quality_multiplier

    Weights & Multipliers:
    - Traffic level: low = 1.0 (0%), medium = 1.15 (+15%), high = 1.30 (+30%)
    - Speed breakers: +0.15 km effective distance penalty per breaker
    - Sharp turns: +0.10 km effective distance penalty per turn
    - Road quality: good = 1.0 (0%), average/moderate = 1.10 (+10%), poor = 1.25 (+25%)
    """
    raw_distance = _number(route.get("distance_km"), 1.0)

    # Speed breaker count
    breakers = route.get("speed_breaker_count")
    if breakers is None:
        breakers = 0.0
    else:
        try:
            breakers = float(breakers)
        except (ValueError, TypeError):
            breakers = 0.0

    sharp_turns = 0.0
    if route.get("sharp_turn_count") is not None:
        try:
            sharp_turns = float(route.get("sharp_turn_count"))
        except (ValueError, TypeError):
            sharp_turns = 0.0

    traffic_str = str(route.get("traffic_level") or "medium").lower().strip()
    traffic_mult_map = {"low": 1.0, "medium": 1.15, "high": 1.30}
    traffic_mult = traffic_mult_map.get(traffic_str, 1.15)

    quality_str = str(route.get("road_quality") or "average").lower().strip()
    quality_mult_map = {"good": 1.0, "average": 1.10, "moderate": 1.10, "poor": 1.25}
    quality_mult = quality_mult_map.get(quality_str, 1.10)

    effective_dist = (raw_distance + (0.15 * breakers) + (0.10 * sharp_turns)) * traffic_mult * quality_mult
    return round(float(effective_dist), 2)


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
    """Computes a 0-100 route difficulty score from admin-entered fields."""
    traffic = route.get("traffic_level")
    breakers = route.get("speed_breaker_count")
    narrow = route.get("sharp_turn_count") or route.get("num_narrow_road_sections")
    quality = route.get("road_quality")

    if traffic is None and breakers is None and narrow is None and quality is None:
        return None

    traffic_map = {"low": 10.0, "medium": 50.0, "high": 90.0}
    quality_map = {"good": 10.0, "average": 50.0, "moderate": 50.0, "poor": 90.0}

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
    narrow_sections = route.get("sharp_turn_count") or route.get("num_narrow_road_sections") or 0
    speed_breakers = route.get("speed_breaker_count") or 0
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


def call_gemini_api_for_explanation(payload_json: dict) -> str:
    """
    Calls Google Gemini Flash API to phrase structured pre-calculated optimization results into plain English.
    STRICT CONSTRAINT: Gemini is forbidden from calculating, altering, or modifying any numbers.
    """
    api_key = os.getenv("GEMINI_API_KEY")
    if not api_key or api_key == "your_gemini_api_key_here":
        logger.info("[Gemini API] GEMINI_API_KEY not configured in backend/.env — using deterministic fallback explanation.")
        return payload_json.get("fallback_explanation", "Deterministic recommendation generated.")

    prompt_text = (
        "IMPORTANT: You are an AI assistant explaining school bus fleet optimizer recommendations for school administrators.\n"
        "STRICT CONSTRAINT: You must ONLY phrase the provided pre-calculated numbers and facts into a clear, concise, natural plain-English summary (2-3 sentences max).\n"
        "YOU MUST NEVER CALCULATE, ALTER, INVENT, OR MODIFY ANY NUMBERS YOURSELF. Rely strictly on the exact numbers provided in the JSON payload.\n\n"
        f"PRE-CALCULATED STRUCTURED PAYLOAD:\n{json.dumps(payload_json, indent=2)}\n\n"
        "Plain-English Summary:"
    )

    logger.info(f"[Gemini API Request] Sending structured payload to Gemini Flash API:\n{json.dumps(payload_json)}")

    # Try gemini-2.5-flash endpoint, fallback to gemini-1.5-flash
    models = ["gemini-2.5-flash", "gemini-1.5-flash"]
    for model in models:
        url = f"https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent?key={api_key}"
        headers = {"Content-Type": "application/json"}
        body = {
            "contents": [{"parts": [{"text": prompt_text}]}],
            "generationConfig": {"temperature": 0.2, "maxOutputTokens": 150}
        }
        try:
            res = requests.post(url, headers=headers, json=body, timeout=8)
            if res.status_code == 200:
                res_data = res.json()
                text = res_data["candidates"][0]["content"]["parts"][0]["text"].strip()
                logger.info(f"[Gemini API Response] Received explanation from {model}:\n{text}")
                return text
            else:
                logger.warning(f"[Gemini API] Model {model} returned HTTP {res.status_code}: {res.text}")
        except Exception as e:
            logger.error(f"[Gemini API Error] Failed call to {model}: {e}")

    logger.info("[Gemini API Fallback] API calls unsuccessful — returning deterministic template phrasing.")
    return payload_json.get("fallback_explanation", "Deterministic recommendation generated.")


def _parse_weight(w, default: float) -> float:
    if w is None:
        return default
    if hasattr(w, "default"):
        return float(w.default) if w.default is not None else default
    return float(w)

@router.get("/admin/optimize-routes")
def optimize_routes(
    w_cost: Optional[float] = Query(0.35, ge=0),
    w_time: Optional[float] = Query(0.25, ge=0),
    w_capacity: Optional[float] = Query(0.20, ge=0),
    w_condition: Optional[float] = Query(0.10, ge=0),
    w_compatibility: Optional[float] = Query(0.10, ge=0),
    school_id: Optional[str] = Query(None, description="Optional school scope for an admin"),
):
    """Assign each available bus and route once using the Hungarian algorithm and effective route distances."""
    wc = _parse_weight(w_cost, 0.35)
    wt = _parse_weight(w_time, 0.25)
    wcap = _parse_weight(w_capacity, 0.20)
    wcond = _parse_weight(w_condition, 0.10)
    wcomp = _parse_weight(w_compatibility, 0.10)

    weights = np.array([wc, wt, wcap, wcond, wcomp], dtype=float)
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
            "monthly_savings_inr": 0.0,
            "unassigned_bus_count": len(buses),
            "unassigned_route_count": len(routes),
            "ai_insights_summary": "No active buses or routes found to optimize.",
            "comparison": {
                "before": {"diesel_cost": 0.0, "co2_kg": 0.0, "monthly_cost": 0.0},
                "after": {"diesel_cost": 0.0, "co2_kg": 0.0, "monthly_cost": 0.0},
                "improvement": {"cost_savings_pct": 0.0, "co2_reduction_pct": 0.0, "monthly_savings_inr": 0.0},
            },
        }

    n_buses, n_routes = len(buses), len(routes)
    diesel_costs = np.zeros((n_buses, n_routes), dtype=float)
    travel_times = np.zeros((n_buses, n_routes), dtype=float)
    co2_values = np.zeros((n_buses, n_routes), dtype=float)
    capacity_scores = np.zeros((n_buses, n_routes), dtype=float)
    capacity_labels: list[list[str]] = [["" for _ in routes] for _ in buses]
    eligible_matrix = np.ones((n_buses, n_routes), dtype=bool)

    route_effective_distances = [compute_effective_distance(r) for r in routes]
    route_difficulties = [_compute_route_difficulty(r) for r in routes]
    compatibility_scores = np.zeros((n_buses, n_routes), dtype=float)

    for bus_index, bus in enumerate(buses):
        mileage = _number(bus.get("mileage_kmpl"), DEFAULT_MILEAGE_KMPL)
        diesel_price = _number(bus.get("diesel_price_per_l"), DEFAULT_DIESEL_PRICE_PER_L)
        capacity = _number(bus.get("capacity"), 40.0)

        for route_index, route in enumerate(routes):
            eff_dist = route_effective_distances[route_index]
            students = max(0.0, _number(route.get("student_count"), 0.0) if route.get("student_count") is not None else 0.0)

            litres = eff_dist / mileage
            diesel_costs[bus_index, route_index] = litres * diesel_price
            co2_values[bus_index, route_index] = litres * DIESEL_CO2_KG_PER_L
            travel_times[bus_index, route_index] = eff_dist / FREE_FLOW_SPEED_KMPH

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
        eff_dist = route_effective_distances[route_index]

        fallback_text = (
            f"{bus_label} matched to {route_label} (Effective distance: {eff_dist}km, "
            f"Est. Daily Cost: ₹{diesel_costs[bus_index, route_index]:.2f})."
        )

        gemini_payload = {
            "bus": bus_label,
            "route": route_label,
            "effective_distance_km": eff_dist,
            "raw_distance_km": _number(route.get("distance_km"), 1.0),
            "speed_breaker_count": route.get("speed_breaker_count") or route.get("num_speed_breakers") or 0,
            "sharp_turn_count": route.get("sharp_turn_count") or 0,
            "traffic_level": route.get("traffic_level") or "medium",
            "road_quality": route.get("road_quality") or "average",
            "daily_diesel_cost_inr": round(float(diesel_costs[bus_index, route_index]), 2),
            "capacity_fit": fit_label,
            "fallback_explanation": fallback_text,
        }

        ai_explanation = call_gemini_api_for_explanation(gemini_payload)

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
            "effective_distance_km": eff_dist,
            "capacity_fit": fit_label,
            "explanation": ai_explanation,
        })

    # Naive baseline comparison (first bus to first route, second bus to second route)
    baseline_diesel_cost = 0.0
    baseline_co2_kg = 0.0
    for i in range(min(n_buses, n_routes)):
        baseline_diesel_cost += diesel_costs[i, i]
        baseline_co2_kg += co2_values[i, i]

    opt_diesel_cost = sum(item["diesel_cost"] for item in assignments)
    opt_co2_kg = sum(item["co2_kg"] for item in assignments)

    baseline_monthly = baseline_diesel_cost * OPERATIONAL_DAYS_PER_MONTH
    opt_monthly = opt_diesel_cost * OPERATIONAL_DAYS_PER_MONTH
    monthly_savings_inr = round(max(0.0, baseline_monthly - opt_monthly), 2)

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
            "monthly_cost": round(baseline_monthly, 2),
        },
        "after": {
            "diesel_cost": round(opt_diesel_cost, 2),
            "co2_kg": round(opt_co2_kg, 2),
            "monthly_cost": round(opt_monthly, 2),
        },
        "improvement": {
            "cost_savings_pct": cost_savings_pct,
            "co2_reduction_pct": co2_reduction_pct,
            "cost_saved": round(max(0.0, baseline_diesel_cost - opt_diesel_cost), 2),
            "co2_saved": round(max(0.0, baseline_co2_kg - opt_co2_kg), 2),
            "monthly_savings_inr": monthly_savings_inr,
        },
    }

    # Summary insight payload for Dashboard AI Panel
    dashboard_payload = {
        "assignments_count": len(assignments),
        "monthly_savings_inr": monthly_savings_inr,
        "co2_reduction_pct": co2_reduction_pct,
        "cost_savings_pct": cost_savings_pct,
        "fallback_explanation": (
            f"Hungarian Route Optimization re-aligned {len(assignments)} vehicles using route condition scoring "
            f"(traffic, speed breakers, sharp turns, road quality), saving an estimated ₹{monthly_savings_inr:.0f}/month "
            f"({cost_savings_pct:.1f}% fuel cost reduction)."
        ),
    }

    ai_insights_summary = call_gemini_api_for_explanation(dashboard_payload)

    return {
        "assignments": assignments,
        "matrix": [[round(float(value), 4) for value in row] for row in suitability.tolist()],
        "buses": [{"id": bus.get("id"), "label": _label(bus, "bus_number", "bus_code")} for bus in buses],
        "routes": [{"id": route.get("id"), "label": _label(route, "route_name", "id")} for route in routes],
        "total_diesel_cost": round(opt_diesel_cost, 2),
        "total_co2_kg": round(opt_co2_kg, 2),
        "monthly_savings_inr": monthly_savings_inr,
        "unassigned_bus_count": n_buses - len(assignments),
        "unassigned_route_count": n_routes - len(assignments),
        "ai_insights_summary": ai_insights_summary,
        "comparison": comparison,
    }


@router.put("/admin/routes/{route_id}/condition")
def update_route_condition(route_id: str, data: dict[str, Any] = Body(...)):
    """Admin updates route condition parameters (traffic_level, road_quality, speed_breaker_count, sharp_turn_count)."""
    allowed_keys = {
        "traffic_level",
        "speed_breaker_count",
        "sharp_turn_count",
        "num_narrow_road_sections",
        "road_quality",
        "avg_speed_kmph",
        "peak_congestion_window",
    }
    raw_data = {k: v for k, v in data.items() if k in allowed_keys}
    if not raw_data:
        raise HTTPException(400, "No valid route condition fields provided")

    update_data = {}
    valid_traffic = {"low", "medium", "high"}
    valid_quality = {"good", "average", "moderate", "poor"}

    for key, val in raw_data.items():
        if val == "" or val is None:
            update_data[key] = None
        elif key in ("speed_breaker_count", "sharp_turn_count", "num_narrow_road_sections"):
            try:
                update_data[key] = int(val)
            except (ValueError, TypeError):
                update_data[key] = None
        elif key == "avg_speed_kmph":
            try:
                update_data[key] = float(val)
            except (ValueError, TypeError):
                update_data[key] = None
        elif key == "traffic_level":
            val_str = str(val).lower().strip()
            update_data[key] = val_str if val_str in valid_traffic else None
        elif key == "road_quality":
            val_str = str(val).lower().strip()
            update_data[key] = val_str if val_str in valid_quality else None
        else:
            update_data[key] = str(val) if val else None

    try:
        result = supabase.table("routes").update(update_data).eq("id", route_id).execute()
        return {"status": "success", "data": result.data}
    except Exception as e:
        raise HTTPException(400, f"Failed to update route condition: {str(e)}")
