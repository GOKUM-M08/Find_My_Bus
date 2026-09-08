import unittest
import asyncio
import os
import sys

# Add backend directory to sys.path
sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))

from unittest.mock import MagicMock, patch
from database import redis_client
from routes.tracking import (
    haversine_distance,
    get_ordered_stops,
    check_and_flip_trip_direction,
    FINAL_STOP_RADIUS_KM
)

class TestTripDirection(unittest.TestCase):

    def setUp(self):
        self.bus_id = "test-bus-123"
        self.route_id = "test-route-456"
        # Clean up Redis keys before each test
        redis_client.delete(f"bus:{self.bus_id}:trip_direction")
        redis_client.delete(f"bus:{self.bus_id}:flipped_at_stop-3")
        redis_client.delete(f"bus:{self.bus_id}:flipped_at_stop-1")

        self.mock_stops = [
            {"id": "stop-1", "stop_name": "Depot/Start", "latitude": 13.0000, "longitude": 80.0000, "stop_order": 1},
            {"id": "stop-2", "stop_name": "Midpoint", "latitude": 13.0100, "longitude": 80.0100, "stop_order": 2},
            {"id": "stop-3", "stop_name": "School/Final", "latitude": 13.0200, "longitude": 80.0200, "stop_order": 3},
        ]

    def tearDown(self):
        redis_client.delete(f"bus:{self.bus_id}:trip_direction")
        redis_client.delete(f"bus:{self.bus_id}:flipped_at_stop-3")
        redis_client.delete(f"bus:{self.bus_id}:flipped_at_stop-1")

    @patch("routes.tracking.supabase")
    def test_get_ordered_stops_morning(self, mock_supabase):
        mock_route = MagicMock()
        mock_route.execute.return_value.data = [{"id": self.route_id}]
        mock_supabase.table.return_value.select.return_value.eq.return_value = mock_route

        mock_stops = MagicMock()
        mock_stops.execute.return_value.data = self.mock_stops
        mock_supabase.table.return_value.select.return_value.eq.return_value.order.return_value = mock_stops

        stops = get_ordered_stops(self.bus_id)
        self.assertEqual(len(stops), 3)
        self.assertEqual(stops[0]["id"], "stop-1")
        self.assertEqual(stops[-1]["id"], "stop-3")

    @patch("routes.tracking.supabase")
    def test_get_ordered_stops_evening(self, mock_supabase):
        redis_client.set(f"bus:{self.bus_id}:trip_direction", "evening")

        mock_route = MagicMock()
        mock_route.execute.return_value.data = [{"id": self.route_id}]
        mock_supabase.table.return_value.select.return_value.eq.return_value = mock_route

        mock_stops = MagicMock()
        mock_stops.execute.return_value.data = self.mock_stops
        mock_supabase.table.return_value.select.return_value.eq.return_value.order.return_value = mock_stops

        stops = get_ordered_stops(self.bus_id)
        self.assertEqual(len(stops), 3)
        self.assertEqual(stops[0]["id"], "stop-3")
        self.assertEqual(stops[-1]["id"], "stop-1")

    @patch("routes.tracking.supabase")
    def test_auto_flip_on_final_stop_arrival(self, mock_supabase):
        def mock_table(table_name):
            m = MagicMock()
            if table_name == "routes":
                m.select.return_value.eq.return_value.execute.return_value.data = [{"id": self.route_id}]
            elif table_name == "stops":
                m.select.return_value.eq.return_value.order.return_value.execute.return_value.data = self.mock_stops
            return m

        mock_supabase.table.side_effect = mock_table

        # 1. Bus far from final stop
        asyncio.run(check_and_flip_trip_direction(self.bus_id, 13.0000, 80.0000))
        dir_val = redis_client.get(f"bus:{self.bus_id}:trip_direction") or b"morning"
        self.assertEqual(dir_val.decode() if isinstance(dir_val, bytes) else dir_val, "morning")

        # 2. Bus arrives near final stop (stop-3)
        final_lat, final_lon = 13.0200, 80.0200
        asyncio.run(check_and_flip_trip_direction(self.bus_id, final_lat, final_lon))
        dir_val = redis_client.get(f"bus:{self.bus_id}:trip_direction")
        self.assertEqual(dir_val.decode() if isinstance(dir_val, bytes) else dir_val, "evening")

        # Debounce key set
        debounced = redis_client.get(f"bus:{self.bus_id}:flipped_at_stop-3")
        self.assertIsNotNone(debounced)

        # 3. Second update while lingering near final stop — should stay evening
        asyncio.run(check_and_flip_trip_direction(self.bus_id, final_lat, final_lon))
        dir_val = redis_client.get(f"bus:{self.bus_id}:trip_direction")
        self.assertEqual(dir_val.decode() if isinstance(dir_val, bytes) else dir_val, "evening")

        # 4. Bus moves away from stop-3
        asyncio.run(check_and_flip_trip_direction(self.bus_id, 13.0100, 80.0100))
        debounced = redis_client.get(f"bus:{self.bus_id}:flipped_at_stop-3")
        self.assertIsNone(debounced)

        # 5. Bus arrives at evening final stop (stop-1)
        asyncio.run(check_and_flip_trip_direction(self.bus_id, 13.0000, 80.0000))
        dir_val = redis_client.get(f"bus:{self.bus_id}:trip_direction")
        self.assertEqual(dir_val.decode() if isinstance(dir_val, bytes) else dir_val, "morning")

if __name__ == "__main__":
    unittest.main()
