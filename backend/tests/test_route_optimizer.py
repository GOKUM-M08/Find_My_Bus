"""Focused contract test for the rectangular Hungarian assignment path."""

import sys
import types
import unittest
from types import SimpleNamespace

# Keep this deterministic unit test independent of local Supabase credentials.
database_stub = types.ModuleType("database")
database_stub.supabase = None
sys.modules.setdefault("database", database_stub)
sys.path.insert(0, "backend")

from routes import route_optimizer  # noqa: E402


class _Query:
    def __init__(self, rows):
        self.rows = rows

    def select(self, *_args):
        return self

    def eq(self, *_args):
        return self

    def execute(self):
        return SimpleNamespace(data=self.rows)


class _Supabase:
    def __init__(self):
        self.data = {
            "buses": [
                {"id": "b1", "bus_number": "Bus 1", "mileage_kmpl": 5, "capacity": 45, "condition_score": .9, "diesel_price_per_l": 90},
                {"id": "b2", "bus_number": "Bus 2", "mileage_kmpl": 3, "capacity": 25, "condition_score": .8, "diesel_price_per_l": 90},
                {"id": "b3", "bus_number": "Bus 3", "mileage_kmpl": 4, "capacity": 70, "condition_score": 1, "diesel_price_per_l": 90},
            ],
            "routes": [
                {"id": "r1", "route_name": "North", "distance_km": 20, "student_count": 40, "traffic_index": 1.2},
                {"id": "r2", "route_name": "South", "distance_km": 10, "student_count": 20, "traffic_index": .9},
            ],
        }

    def table(self, name):
        return _Query(self.data[name])


class RouteOptimizerTest(unittest.TestCase):
    def test_rectangular_assignment_is_unique_and_explainable(self):
        previous = route_optimizer.supabase
        route_optimizer.supabase = _Supabase()
        try:
            result = route_optimizer.optimize_routes(.4, .3, .2, .1, None)
        finally:
            route_optimizer.supabase = previous

        self.assertEqual(2, len(result["assignments"]))
        self.assertEqual(3, len(result["matrix"]))
        self.assertEqual(2, len(result["matrix"][0]))
        self.assertEqual(1, result["unassigned_bus_count"])
        self.assertEqual(0, result["unassigned_route_count"])
        self.assertEqual(2, len({item["bus"]["id"] for item in result["assignments"]}))
        self.assertEqual(2, len({item["route"]["id"] for item in result["assignments"]}))
        self.assertGreater(result["total_diesel_cost"], 0)
        self.assertGreater(result["total_co2_kg"], 0)
        self.assertTrue(all(item["explanation"] for item in result["assignments"]))


if __name__ == "__main__":
    unittest.main()
