import unittest
import os
import sys

sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))

from unittest.mock import MagicMock, patch
from routes.route_optimizer import update_route_condition

class TestRouteConditionUpdate(unittest.TestCase):

    @patch("routes.route_optimizer.supabase")
    def test_update_route_condition_empty_strings(self, mock_supabase):
        mock_supabase.table.return_value.update.return_value.eq.return_value.execute.return_value.data = [{"id": "r1"}]

        # Payload with empty strings
        data = {
            "traffic_level": "",
            "speed_breaker_count": "",
            "num_narrow_road_sections": "",
            "road_quality": "",
            "avg_speed_kmph": "",
            "peak_congestion_window": ""
        }

        res = update_route_condition("r1", data)
        self.assertEqual(res["status"], "success")

        # Verify update call received None for empty strings instead of ""
        expected_update = {
            "traffic_level": None,
            "speed_breaker_count": None,
            "num_narrow_road_sections": None,
            "road_quality": None,
            "avg_speed_kmph": None,
            "peak_congestion_window": None
        }
        mock_supabase.table.return_value.update.assert_called_with(expected_update)

    @patch("routes.route_optimizer.supabase")
    def test_update_route_condition_valid_data(self, mock_supabase):
        mock_supabase.table.return_value.update.return_value.eq.return_value.execute.return_value.data = [{"id": "r1"}]

        data = {
            "traffic_level": "medium",
            "speed_breaker_count": "5",
            "num_narrow_road_sections": "2",
            "road_quality": "good",
            "avg_speed_kmph": "35.5"
        }

        res = update_route_condition("r1", data)
        self.assertEqual(res["status"], "success")

        expected_update = {
            "traffic_level": "medium",
            "speed_breaker_count": 5,
            "num_narrow_road_sections": 2,
            "road_quality": "good",
            "avg_speed_kmph": 35.5
        }
        mock_supabase.table.return_value.update.assert_called_with(expected_update)

if __name__ == "__main__":
    unittest.main()
