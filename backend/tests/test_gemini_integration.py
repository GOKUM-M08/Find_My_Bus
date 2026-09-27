import pytest
from routes.route_optimizer import call_gemini_api_for_explanation, compute_effective_distance, optimize_routes

def test_effective_distance_formula():
    """Verify exact formula: (raw + 0.15*breakers + 0.10*turns) * traffic_mult * quality_mult."""
    route = {
        "distance_km": 10.0,
        "speed_breaker_count": 4,      # 4 * 0.15 = 0.60
        "sharp_turn_count": 2,          # 2 * 0.10 = 0.20
        "traffic_level": "medium",      # 1.15
        "road_quality": "good",         # 1.0
    }
    # Expected: (10.0 + 0.60 + 0.20) * 1.15 * 1.0 = 10.80 * 1.15 = 12.42
    eff = compute_effective_distance(route)
    assert eff == 12.42

def test_gemini_prompt_constraint_formatting():
    """Verify payload phrasing function accepts pre-calculated data and returns a valid string."""
    payload = {
        "bus": "TN-09-AB-1234",
        "route": "North Pickup Route",
        "monthly_savings_inr": 1250.0,
        "effective_distance_km": 12.42,
        "fallback_explanation": "TN-09-AB-1234 matched to North Pickup Route (Monthly savings: ₹1250)."
    }
    result = call_gemini_api_for_explanation(payload)
    assert isinstance(result, str)
    assert len(result) > 5

def test_optimizer_endpoint_returns_ai_insights():
    """Verify optimize_routes endpoint returns ai_insights_summary and assignments with explanations."""
    res = optimize_routes(w_cost=0.5, w_time=0.1)
    assert "ai_insights_summary" in res
    assert "assignments" in res
