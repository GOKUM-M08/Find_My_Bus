"""
tests/test_phase1_simulation.py

Simulation test for Phase 1 requirements:
- Real routes: Route 394 and Route 395.
- Simulated bus movement every ~40m (35 km/h, 4-second intervals).
- Monotonic progress verification (stops_away never increases).
- Status: arrived within 150m, passed after leaving.
- No flicker near midpoints between stops.
- Offline status when no GPS update for > 90 seconds.
- Zero Supabase calls on warm updates (in-memory caching).
- Trip direction self-heal from evening to morning.
"""

import sys
import os
sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))

import time
import math
import asyncio
import pytest
from unittest.mock import MagicMock, patch
from services.broadcast import save_bus_position
from routes.tracking import (
    haversine_distance,
    get_eta,
    get_ordered_stops,
    check_and_flip_trip_direction,
    clear_stops_cache,
    update_bus_progress,
    _stops_cache,
    STOP_REACHED_RADIUS_KM,
    ROAD_FACTOR,
)


class FakeRedis:
    """In-memory fast fake Redis for deterministic simulation testing."""
    def __init__(self):
        self._data = {}
        self._hashes = {}

    def get(self, key):
        return self._data.get(key)

    def set(self, key, value, ex=None):
        self._data[key] = str(value) if value is not None else ""
        return True

    def delete(self, *keys):
        for k in keys:
            self._data.pop(k, None)
            self._hashes.pop(k, None)
        return True

    def hgetall(self, name):
        return dict(self._hashes.get(name, {}))

    def hset(self, name, key=None, value=None, mapping=None):
        if name not in self._hashes:
            self._hashes[name] = {}
        if mapping:
            for k, v in mapping.items():
                self._hashes[name][str(k)] = str(v)
        if key is not None and value is not None:
            self._hashes[name][str(key)] = str(value)
        return True

    def expire(self, name, time):
        return True


# Route 394 coordinates
ROUTE_394_STOPS = [
    {"id": "394-1", "stop_name": "Tiruvallur", "latitude": 13.140416, "longitude": 79.908266, "stop_order": 1, "expected_time": "06:45 AM"},
    {"id": "394-2", "stop_name": "Palavedu", "latitude": 13.154577, "longitude": 80.054244, "stop_order": 2, "expected_time": "07:05 AM"},
    {"id": "394-3", "stop_name": "Redhills", "latitude": 13.186465, "longitude": 80.199878, "stop_order": 3, "expected_time": "07:25 AM"},
    {"id": "394-4", "stop_name": "Sholavaram", "latitude": 13.235960, "longitude": 80.163459, "stop_order": 4, "expected_time": "07:40 AM"},
    {"id": "394-5", "stop_name": "Karanodai", "latitude": 13.250632, "longitude": 80.160910, "stop_order": 5, "expected_time": "07:50 AM"},
    {"id": "394-6", "stop_name": "RMKCET", "latitude": 13.322098, "longitude": 80.149773, "stop_order": 6, "expected_time": "08:10 AM"},
]

# Route 395 coordinates
ROUTE_395_STOPS = [
    {"id": "395-1", "stop_name": "Thandalam", "latitude": 13.3135311, "longitude": 80.0040843, "stop_order": 1, "expected_time": "07:10 AM"},
    {"id": "395-2", "stop_name": "Periyapalayam", "latitude": 13.3090970, "longitude": 80.0455200, "stop_order": 2, "expected_time": "07:25 AM"},
    {"id": "395-3", "stop_name": "Arani", "latitude": 13.3306430, "longitude": 80.0842260, "stop_order": 3, "expected_time": "07:45 AM"},
    {"id": "395-4", "stop_name": "RMKCET", "latitude": 13.3220979, "longitude": 80.1497731, "stop_order": 4, "expected_time": "08:05 AM"},
]


def interpolate_points(lat1, lon1, lat2, lon2, step_meters=40.0):
    """Generate intermediate GPS points spaced ~40m apart between two coordinates."""
    dist_km = haversine_distance(lat1, lon1, lat2, lon2)
    dist_m = dist_km * 1000.0
    steps = max(1, int(dist_m / step_meters))
    points = []
    for step in range(steps + 1):
        frac = step / steps
        lat = lat1 + (lat2 - lat1) * frac
        lon = lon1 + (lon2 - lon1) * frac
        points.append((lat, lon))
    return points


def setup_mock_supabase(stops_list, bus_id="test-bus-sim", route_id="test-route-sim"):
    mock_sb = MagicMock()

    def mock_table(table_name):
        table_mock = MagicMock()
        if table_name == "routes":
            table_mock.select.return_value.eq.return_value.execute.return_value.data = [{"id": route_id}]
        elif table_name == "stops":
            table_mock.select.return_value.eq.return_value.order.return_value.execute.return_value.data = stops_list
        elif table_name == "buses":
            table_mock.select.return_value.eq.return_value.execute.return_value.data = [{"id": bus_id, "bus_number": "394"}]
        return table_mock

    mock_sb.table.side_effect = mock_table
    return mock_sb


class TestPhase1Simulation:

    def setup_method(self):
        clear_stops_cache()
        self.fake_redis = FakeRedis()

    @pytest.mark.parametrize("route_stops, bus_id", [
        (ROUTE_394_STOPS, "bus-394"),
        (ROUTE_395_STOPS, "bus-395"),
    ])
    def test_bus_route_simulation(self, route_stops, bus_id):
        mock_sb = setup_mock_supabase(route_stops, bus_id=bus_id)
        with patch("routes.tracking.supabase", mock_sb), \
             patch("services.broadcast.redis_client", self.fake_redis), \
             patch("routes.tracking.redis_client", self.fake_redis):

            self.fake_redis.set(f"bus:{bus_id}:trip_direction", "morning")

            target_stop = route_stops[-2]  # Second to last stop as target
            target_stop_id = target_stop["id"]
            target_lat = target_stop["latitude"]
            target_lon = target_stop["longitude"]

            prev_stops_away = None
            arrived_detected = False
            passed_detected = False

            # Traverse the entire route from stop 0 to final stop
            for idx in range(len(route_stops) - 1):
                p_start = route_stops[idx]
                p_end = route_stops[idx + 1]
                segment_points = interpolate_points(
                    p_start["latitude"], p_start["longitude"],
                    p_end["latitude"], p_end["longitude"],
                    step_meters=40.0
                )

                for lat, lon in segment_points:
                    # Save position to Redis through unified function
                    save_bus_position(bus_id, lat, lon, speed=35.0)

                    # Update progress
                    current_stops = get_ordered_stops(bus_id, use_cache=True)
                    update_bus_progress(bus_id, lat, lon, current_stops, "morning")

                    # Query ETA for target stop
                    res = get_eta(bus_id, target_stop_id)
                    status = res["status"]
                    dist_to_target = haversine_distance(lat, lon, target_lat, target_lon)

                    # 1. Assert: within 150m of target, status must be arrived (NEVER passed)
                    if dist_to_target <= STOP_REACHED_RADIUS_KM:
                        assert status == "arrived", f"Expected arrived when within 150m, got {status} at dist {dist_to_target*1000}m"
                        arrived_detected = True

                    # 2. Assert: stops_away never increases during approaching trip
                    if status == "approaching":
                        cur_stops_away = res["stops_away"]
                        assert cur_stops_away is not None
                        if prev_stops_away is not None:
                            assert cur_stops_away <= prev_stops_away, (
                                f"stops_away went up from {prev_stops_away} to {cur_stops_away} at ({lat}, {lon})"
                            )
                        prev_stops_away = cur_stops_away

                    # 3. Assert: passed after bus clearly moves past target stop
                    if idx >= len(route_stops) - 2 and dist_to_target > STOP_REACHED_RADIUS_KM and arrived_detected:
                        if status == "passed":
                            passed_detected = True

            assert arrived_detected, "Bus should have entered 'arrived' state at target stop"
            assert passed_detected, "Bus should have transitioned to 'passed' after leaving target stop"

    def test_no_flicker_at_midpoint(self):
        """Assert no flicker occurs at the geometric midpoint between two stops."""
        route_stops = ROUTE_394_STOPS
        bus_id = "bus-394-mid"
        mock_sb = setup_mock_supabase(route_stops, bus_id=bus_id)

        with patch("routes.tracking.supabase", mock_sb), \
             patch("services.broadcast.redis_client", self.fake_redis), \
             patch("routes.tracking.redis_client", self.fake_redis):

            self.fake_redis.set(f"bus:{bus_id}:trip_direction", "morning")

            s1 = route_stops[1]  # Palavedu
            s2 = route_stops[2]  # Redhills

            mid_lat = (s1["latitude"] + s2["latitude"]) / 2.0
            mid_lon = (s1["longitude"] + s2["longitude"]) / 2.0

            # Test multiple small perturbations around midpoint
            statuses = []
            stops_aways = []
            for delta in [-0.0002, -0.0001, 0.0, 0.0001, 0.0002]:
                lat = mid_lat + delta
                lon = mid_lon + delta
                save_bus_position(bus_id, lat, lon, speed=30.0)
                stops = get_ordered_stops(bus_id)
                update_bus_progress(bus_id, lat, lon, stops, "morning")
                res = get_eta(bus_id, s2["id"])
                statuses.append(res["status"])
                stops_aways.append(res["stops_away"])

            # Status should steadily remain approaching without flipping back and forth
            assert all(s == "approaching" for s in statuses)
            # stops_away should be monotonic (never increasing)
            for i in range(len(stops_aways) - 1):
                assert stops_aways[i] >= stops_aways[i + 1]

    def test_offline_when_stale_position(self):
        """Assert that if no GPS update arrives for > 90 seconds, status is offline."""
        bus_id = "bus-stale-test"
        mock_sb = setup_mock_supabase(ROUTE_394_STOPS, bus_id=bus_id)

        with patch("routes.tracking.supabase", mock_sb), \
             patch("services.broadcast.redis_client", self.fake_redis), \
             patch("routes.tracking.redis_client", self.fake_redis):

            stale_epoch = int(time.time() - 120)
            self.fake_redis.hset(f"bus:{bus_id}", mapping={
                "latitude": 13.140416,
                "longitude": 79.908266,
                "speed": 25.0,
                "updated_at": stale_epoch,
            })

            res = get_eta(bus_id, "394-2")
            assert res["status"] == "offline"
            assert res["minutes"] is None
            assert res["stops_away"] is None
            assert res["eta"] == "Bus offline"

    def test_zero_supabase_calls_on_warm_updates(self):
        """Assert that warm position updates make 0 Supabase calls."""
        bus_id = "bus-cache-test"
        mock_sb = setup_mock_supabase(ROUTE_394_STOPS, bus_id=bus_id)

        with patch("routes.tracking.supabase", mock_sb), \
             patch("services.broadcast.redis_client", self.fake_redis), \
             patch("routes.tracking.redis_client", self.fake_redis):

            self.fake_redis.set(f"bus:{bus_id}:trip_direction", "morning")

            # Warm up cache with initial read
            get_ordered_stops(bus_id, use_cache=True)
            initial_count = mock_sb.table.call_count

            # Run 25 consecutive GPS progress updates
            for i in range(25):
                lat = 13.140416 + (i * 0.001)
                lon = 79.908266 + (i * 0.001)
                save_bus_position(bus_id, lat, lon, speed=30.0)
                stops = get_ordered_stops(bus_id, use_cache=True)
                update_bus_progress(bus_id, lat, lon, stops, "morning")
                get_eta(bus_id, "394-4")

            # Must have made 0 new Supabase calls during the 25 warm updates!
            assert mock_sb.table.call_count == initial_count

    def test_direction_self_heal(self):
        """
        Assert self-heal: if direction is evening and bus is within 500m of the FIRST morning stop
        and the last flip was > 3 hours ago, it resets to morning.
        """
        bus_id = "bus-self-heal"
        mock_sb = setup_mock_supabase(ROUTE_394_STOPS, bus_id=bus_id)

        with patch("routes.tracking.supabase", mock_sb), \
             patch("services.broadcast.redis_client", self.fake_redis), \
             patch("routes.tracking.redis_client", self.fake_redis):

            first_stop = ROUTE_394_STOPS[0]
            first_lat = first_stop["latitude"]
            first_lon = first_stop["longitude"]

            # Set trip_direction to evening with flip time 4 hours ago
            self.fake_redis.set(f"bus:{bus_id}:trip_direction", "evening")
            four_hours_ago = time.time() - (4 * 3600)
            self.fake_redis.set(f"bus:{bus_id}:trip_direction_time", four_hours_ago)

            # Bus is 200m away from the first morning stop
            new_dir = asyncio.run(check_and_flip_trip_direction(bus_id, first_lat + 0.001, first_lon + 0.001))

            assert new_dir == "morning"
            saved_dir = self.fake_redis.get(f"bus:{bus_id}:trip_direction")
            assert saved_dir == "morning"
