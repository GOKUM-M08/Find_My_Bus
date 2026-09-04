import pytest
import numpy as np
from routes.route_optimizer import (
    optimize_routes,
    _capacity_fit,
    _compute_route_difficulty,
    _compute_compatibility,
)

def test_overcapacity_ineligible():
    fit_score, fit_label, is_eligible = _capacity_fit(capacity=40, students=50)
    assert is_eligible is False
    assert fit_label == "Overcapacity"

def test_route_difficulty_unentered_returns_none():
    route = {"traffic_level": None, "num_speed_breakers": None, "num_narrow_road_sections": None, "road_quality": None}
    assert _compute_route_difficulty(route) is None

def test_route_difficulty_calculation():
    route = {
        "traffic_level": "medium", # 50 * 0.30 = 15
        "num_speed_breakers": 2,    # 20 * 0.25 = 5
        "num_narrow_road_sections": 1, # 25 * 0.25 = 6.25
        "road_quality": "good",     # 10 * 0.20 = 2
    }
    score = _compute_route_difficulty(route)
    assert score is not None
    assert score == round(15.0 + 5.0 + 6.25 + 2.0, 1)

def test_route_compatibility():
    bus_large = {"bus_type": "large", "suitable_for_narrow_roads": False}
    route_narrow = {"num_narrow_road_sections": 2, "num_speed_breakers": 1}
    diff = 70.0
    score, label = _compute_compatibility(bus_large, route_narrow, diff)
    assert score < 1.0
    assert "narrow" in label.lower() or "large" in label.lower()

def test_optimize_routes_response_structure():
    res = optimize_routes(w_cost=0.35, w_time=0.25, w_capacity=0.20, w_condition=0.10, w_compatibility=0.10)
    assert "assignments" in res
    assert "matrix" in res
    assert "buses" in res
    assert "routes" in res
    assert "total_diesel_cost" in res
    assert "total_co2_kg" in res
    assert "unassigned_bus_count" in res
    assert "unassigned_route_count" in res
    assert "comparison" in res

    if res["assignments"]:
        assign = res["assignments"][0]
        assert "eligible" in assign
        assert "cost_score" in assign
        assert "time_score" in assign
        assert "capacity_score" in assign
        assert "condition_score" in assign
        assert "compatibility_score" in assign
        assert "explanation" in assign

    comp = res["comparison"]
    assert "before" in comp
    assert "after" in comp
    assert "improvement" in comp
    print("Optimization output verified successfully!")

if __name__ == "__main__":
    test_overcapacity_ineligible()
    test_route_difficulty_unentered_returns_none()
    test_route_difficulty_calculation()
    test_route_compatibility()
    test_optimize_routes_response_structure()
    print("ALL PHASE 1 TESTS PASSED PERFECTLY!")
