#!/usr/bin/env python3
"""
backend/scripts/send_test_alert.py

CLI tool to send a real test voice alert via FCM.
Usage:
  python send_test_alert.py --event started --lang ta --bus-id <BUS_ID>
  python send_test_alert.py --event near --lang en --bus-id <BUS_ID> --stop-id <STOP_ID>
  python send_test_alert.py --event arrived --lang ta --bus-id <BUS_ID>
"""

import sys
import os
import argparse

# Add backend directory to sys.path
sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))

from notifications import send_alert
from notification_messages import (
    EVENT_BUS_STARTED,
    EVENT_TWO_STOPS_AWAY,
    EVENT_REACHED_COLLEGE,
    canonicalize_event,
    SUPPORTED_LANGUAGES,
)
from database import supabase


def main():
    parser = argparse.ArgumentParser(description="Send test FCM voice alert to phone.")
    parser.add_argument(
        "--event",
        required=True,
        choices=["started", "near", "arrived", "bus_started", "two_stops_away", "reached_college"],
        help="Event type to simulate",
    )
    parser.add_argument(
        "--lang",
        required=True,
        choices=SUPPORTED_LANGUAGES,
        help="Language for alert (ta or en)",
    )
    parser.add_argument(
        "--bus-id",
        required=True,
        help="Bus ID in database",
    )
    parser.add_argument(
        "--stop-id",
        required=False,
        default=None,
        help="Stop ID (required for 'near' / 'two_stops_away')",
    )
    parser.add_argument(
        "--bus-number",
        required=False,
        default=None,
        help="Custom bus number/label (optional, fetches from DB if omitted)",
    )
    parser.add_argument(
        "--stop-name",
        required=False,
        default=None,
        help="Custom stop name (optional, fetches from DB if omitted)",
    )
    parser.add_argument(
        "--college",
        required=False,
        default=None,
        help="College name (optional, fetches from DB if omitted)",
    )
    parser.add_argument(
        "--min",
        type=int,
        required=False,
        default=5,
        help="Estimated minutes for ETA (default: 5)",
    )

    args = parser.parse_args()
    c_event = canonicalize_event(args.event)

    if c_event == EVENT_TWO_STOPS_AWAY and not args.stop_id:
        print("Error: --stop-id is required for 'near' / 'two_stops_away' event.")
        sys.exit(1)

    # Fetch bus details from Supabase if not provided
    bus_number = args.bus_number
    if not bus_number and supabase:
        try:
            b_res = supabase.table("buses").select("bus_number").eq("id", args.bus_id).execute()
            if b_res.data:
                bus_number = b_res.data[0].get("bus_number")
        except Exception:
            pass
    bus_number = bus_number or args.bus_id

    # Fetch stop details from Supabase if needed
    stop_name = args.stop_name
    college_name = args.college
    if (not stop_name or not college_name) and supabase:
        try:
            if args.stop_id:
                s_res = supabase.table("stops").select("stop_name").eq("id", args.stop_id).execute()
                if s_res.data:
                    stop_name = stop_name or s_res.data[0].get("stop_name")
            # If college needed for arrived
            if c_event == EVENT_REACHED_COLLEGE and not college_name:
                r_res = supabase.table("routes").select("id").eq("bus_id", args.bus_id).execute()
                if r_res.data:
                    route_id = r_res.data[0]["id"]
                    all_stops = supabase.table("stops").select("stop_name").eq("route_id", route_id).order("stop_order").execute()
                    if all_stops.data:
                        college_name = all_stops.data[-1].get("stop_name")
        except Exception:
            pass

    stop_name = stop_name or "Test Stop"
    college_name = college_name or "College"

    variables = {
        "bus": bus_number,
        "stop": stop_name,
        "college": college_name,
        "min": args.min,
    }

    print(f"Sending test alert:")
    print(f"  Event: {c_event}")
    print(f"  Language: {args.lang}")
    print(f"  Bus ID: {args.bus_id} ({bus_number})")
    print(f"  Stop ID: {args.stop_id} ({stop_name})")
    print(f"  Variables: {variables}")

    result = send_alert(
        event=c_event,
        bus_id=args.bus_id,
        stop_id=args.stop_id,
        variables=variables,
    )

    print("Result:", result)


if __name__ == "__main__":
    main()
