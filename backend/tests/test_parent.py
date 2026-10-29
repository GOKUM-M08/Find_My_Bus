import os
import sys
import time
import pytest
from unittest.mock import MagicMock, patch
from fastapi.testclient import TestClient

sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))

from main import app
from routes.parent import (
    normalize_phone,
    _create_token,
    _fails_by_ip,
    _fails_all,
    _cache,
    ONE_YEAR_SECONDS,
    ALGORITHM,
)
from jose import jwt


@pytest.fixture(autouse=True)
def reset_parent_state():
    _fails_by_ip.clear()
    _fails_all.clear()
    _cache.clear()
    os.environ["PARENT_JWT_SECRET"] = "test-secret-key-1234567890"
    yield
    _fails_by_ip.clear()
    _fails_all.clear()
    _cache.clear()


client = TestClient(app)


def test_normalize_phone():
    assert normalize_phone("+91 98765 43210") == "9876543210"
    assert normalize_phone("09876543210") == "9876543210"
    assert normalize_phone("+919876543210") == "9876543210"
    assert normalize_phone("9876543210") == "9876543210"
    assert normalize_phone("98765 43210") == "9876543210"
    assert normalize_phone("12345") is None  # Too short
    assert normalize_phone("") is None
    assert normalize_phone("123456789012345") is None  # Too long


@patch("routes.parent.supabase")
def test_login_validation_and_not_found(mock_supabase):
    # Too short -> 400
    res = client.post("/api/parent/login", json={"phone": "123"})
    assert res.status_code == 400
    assert "valid 10-digit" in res.json()["detail"]

    # Unknown number -> 404
    mock_query = MagicMock()
    mock_query.execute.return_value.data = []
    mock_supabase.table.return_value.select.return_value.or_.return_value = mock_query

    res = client.post("/api/parent/login", json={"phone": "9999999999"})
    assert res.status_code == 404
    assert "not registered" in res.json()["detail"]


@patch("routes.parent.supabase")
def test_login_success_and_second_phone_and_siblings(mock_supabase):
    # Setup 2 students (siblings on 2 buses)
    mock_students = [
        {
            "id": "student-1",
            "student_name": "Child One",
            "parent_name": "Ravi",
            "bus_id": "bus-101",
            "stop_id": "stop-1",
            "school_id": "sch-1",
            "buses": {"id": "bus-101", "bus_number": "101", "bus_code": "B1", "driver_name": "Driver A"},
            "stops": {"id": "stop-1", "stop_name": "Main Gate", "expected_time": "08:00 AM"},
            "schools": {"name": "Green Valley School", "phone": "044-12345678"},
        },
        {
            "id": "student-2",
            "student_name": "Child Two",
            "parent_name": "Ravi",
            "bus_id": "bus-102",
            "stop_id": "stop-2",
            "school_id": "sch-1",
            "buses": {"id": "bus-102", "bus_number": "102", "bus_code": "B2", "driver_name": "Driver B"},
            "stops": {"id": "stop-2", "stop_name": "North Cross", "expected_time": "08:15 AM"},
            "schools": {"name": "Green Valley School", "phone": "044-12345678"},
        },
    ]

    mock_query = MagicMock()
    mock_query.execute.return_value.data = mock_students
    mock_supabase.table.return_value.select.return_value.or_.return_value = mock_query

    # Login with primary or second phone
    res = client.post("/api/parent/login", json={"phone": "+91 98765 43210"})
    assert res.status_code == 200
    data = res.json()
    assert "token" in data
    assert data["phone"] == "9876543210"
    assert len(data["students"]) == 2
    assert data["students"][0]["bus_id"] == "bus-101"
    assert data["students"][1]["bus_id"] == "bus-102"
    assert data["students"][0]["school_phone"] == "044-12345678"


@patch("routes.parent.supabase")
def test_rate_limiting_8_wrong_attempts(mock_supabase):
    mock_query = MagicMock()
    mock_query.execute.return_value.data = []
    mock_supabase.table.return_value.select.return_value.or_.return_value = mock_query

    for i in range(8):
        res = client.post("/api/parent/login", json={"phone": f"900000000{i}"})
        assert res.status_code == 404

    # 9th attempt triggers 429
    res = client.post("/api/parent/login", json={"phone": "9000000009"})
    assert res.status_code == 429
    assert "Too many wrong attempts" in res.json()["detail"]


def test_missing_secret_gives_500():
    del os.environ["PARENT_JWT_SECRET"]
    with patch("routes.parent.supabase") as mock_supabase:
        mock_query = MagicMock()
        mock_query.execute.return_value.data = [{"id": "s1"}]
        mock_supabase.table.return_value.select.return_value.or_.return_value = mock_query

        res = client.post("/api/parent/login", json={"phone": "9876543210"})
        assert res.status_code == 500
        assert "PARENT_JWT_SECRET" in res.json()["detail"]


@patch("routes.parent.supabase")
def test_token_validation_and_access_control(mock_supabase):
    # Missing token -> 401
    res = client.get("/api/parent/me")
    assert res.status_code == 401

    # Garbage token -> 401
    res = client.get("/api/parent/me", headers={"Authorization": "Bearer garbage-token"})
    assert res.status_code == 401

    # Expired token -> 401
    expired_payload = {
        "sub": "9876543210",
        "phone": "9876543210",
        "type": "parent",
        "exp": int(time.time()) - 100,
    }
    expired_token = jwt.encode(expired_payload, "test-secret-key-1234567890", algorithm=ALGORITHM)
    res = client.get("/api/parent/me", headers={"Authorization": f"Bearer {expired_token}"})
    assert res.status_code == 401

    # Wrong type token -> 401
    admin_payload = {
        "sub": "9876543210",
        "phone": "9876543210",
        "type": "admin",
        "exp": int(time.time()) + 1000,
    }
    admin_token = jwt.encode(admin_payload, "test-secret-key-1234567890", algorithm=ALGORITHM)
    res = client.get("/api/parent/me", headers={"Authorization": f"Bearer {admin_token}"})
    assert res.status_code == 401

    # Valid token but number removed by school (returns empty) -> 401
    valid_token = _create_token("9876543210")
    mock_query_empty = MagicMock()
    mock_query_empty.execute.return_value.data = []
    mock_supabase.table.return_value.select.return_value.or_.return_value = mock_query_empty

    res = client.get("/api/parent/me", headers={"Authorization": f"Bearer {valid_token}"})
    assert res.status_code == 401
    assert "no longer registered" in res.json()["detail"]

    # Active parent with bus-101
    _cache.clear()
    mock_active = MagicMock()
    mock_active.execute.return_value.data = [
        {"id": "s1", "student_name": "Test", "bus_id": "bus-101", "buses": {}, "stops": {}, "schools": {}}
    ]
    mock_supabase.table.return_value.select.return_value.or_.return_value = mock_active

    # Can access own bus route
    with patch("routes.parent.get_ordered_stops", return_value=[]):
        mock_route = MagicMock()
        mock_route.execute.return_value.data = [{"id": "r1", "bus_id": "bus-101"}]
        mock_supabase.table.return_value.select.return_value.eq.return_value = mock_route

        res = client.get("/api/parent/bus/bus-101/route", headers={"Authorization": f"Bearer {valid_token}"})
        assert res.status_code == 200

    # Cannot access another bus -> 403
    res = client.get("/api/parent/bus/bus-999/route", headers={"Authorization": f"Bearer {valid_token}"})
    assert res.status_code == 403
    assert "not linked to your account" in res.json()["detail"]


@patch("routes.parent.supabase")
def test_websocket_token_and_bus_permission(mock_supabase):
    mock_active = MagicMock()
    mock_active.execute.return_value.data = [
        {"id": "s1", "bus_id": "bus-101", "buses": {}, "stops": {}, "schools": {}}
    ]
    mock_supabase.table.return_value.select.return_value.or_.return_value = mock_active

    valid_token = _create_token("9876543210")

    # Missing token -> rejected with 4401
    with pytest.raises(Exception):
        with client.websocket_connect("/ws/track/bus-101") as ws:
            pass

    # Wrong bus -> rejected with 4401
    with pytest.raises(Exception):
        with client.websocket_connect(f"/ws/track/bus-999?token={valid_token}") as ws:
            pass

    # Correct bus & valid token -> accepted
    with client.websocket_connect(f"/ws/track/bus-101?token={valid_token}") as ws:
        # Connected successfully
        assert ws is not None


@patch("routes.parent.supabase")
def test_voice_assistant_parent_endpoints(mock_supabase):
    _cache.clear()
    mock_active = MagicMock()
    mock_active.execute.return_value.data = [
        {"id": "s1", "bus_id": "bus-101", "buses": {}, "stops": {}, "schools": {}}
    ]
    mock_supabase.table.return_value.select.return_value.or_.return_value = mock_active

    valid_token = _create_token("9876543210")
    headers = {"Authorization": f"Bearer {valid_token}"}

    with patch("routes.parent.get_bus_location_summary", return_value={"nearest_landmark": "Stop A", "distance_km": 0.5}), \
         patch("routes.parent.get_eta_default", return_value={"eta_minutes": 5, "eta": "5 min", "stops_away": 2}), \
         patch("routes.parent.get_bus_status", return_value={"is_late": False, "delay_minutes": 0}), \
         patch("routes.parent.get_stops_away", return_value={"stops_away": 2}):

        # Test location
        res = client.get("/api/parent/bus/bus-101/location", headers=headers)
        assert res.status_code == 200
        assert res.json()["nearest_landmark"] == "Stop A"

        # Test eta
        res = client.get("/api/parent/bus/bus-101/eta", headers=headers)
        assert res.status_code == 200
        assert res.json()["eta_minutes"] == 5

        # Test status
        res = client.get("/api/parent/bus/bus-101/status", headers=headers)
        assert res.status_code == 200
        assert res.json()["is_late"] is False

        # Test stops-away
        res = client.get("/api/parent/bus/bus-101/stops-away", headers=headers)
        assert res.status_code == 200
        assert res.json()["stops_away"] == 2

        # Test 403 on another bus
        for endpoint in ["location", "eta", "status", "stops-away"]:
            res_wrong = client.get(f"/api/parent/bus/bus-999/{endpoint}", headers=headers)
            assert res_wrong.status_code == 403
            assert "not linked to your account" in res_wrong.json()["detail"]


def test_check_and_notify_parents_message_text():
    import asyncio

    async def _run_test():
        from routes.tracking import check_and_notify_parents, _notified_stops
        _notified_stops.clear()

        with patch("routes.tracking.redis_client") as mock_redis, \
             patch("routes.tracking.supabase") as mock_sb, \
             patch("routes.tracking.get_ordered_stops") as mock_stops, \
             patch("routes.tracking.get_eta") as mock_eta, \
             patch("routes.tracking.send_bus_notification") as mock_send:

            mock_redis.hgetall.return_value = {}
            mock_sb.table.return_value.select.return_value.eq.return_value.execute.return_value.data = [
                {"bus_number": "42", "id": "route-1"}
            ]
            mock_stops.return_value = [{"id": "st-1", "stop_name": "Park Gate"}]

            # Test stops_away = 1 -> "Bus is 1 stop away from Park Gate! Arriving in ~3 min."
            mock_eta.return_value = {"stops_away": 1, "minutes": 3}
            await check_and_notify_parents("bus-101")

            assert mock_send.call_count == 1
            call_kwargs = mock_send.call_args.kwargs
            assert call_kwargs["message"] == "Bus is 1 stop away from Park Gate! Arriving in ~3 min."
            assert call_kwargs["topic"] == "bus_bus-101_stop_st-1"

            # Clear and test stops_away = 2 -> "Bus is 2 stops away from Park Gate! Arriving in ~6 min."
            _notified_stops.clear()
            mock_eta.return_value = {"stops_away": 2, "minutes": 6}
            await check_and_notify_parents("bus-101")

            assert mock_send.call_count == 2
            call_kwargs2 = mock_send.call_args.kwargs
            assert call_kwargs2["message"] == "Bus is 2 stops away from Park Gate! Arriving in ~6 min."

    asyncio.run(_run_test())


