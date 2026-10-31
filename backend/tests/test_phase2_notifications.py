"""
tests/test_phase2_notifications.py

Tests for Phase 2:
- Each event (bus_started, two_stops_away, reached_college) is sent with correct topics,
  both languages (ta, en), correct channel IDs, sounds, priority, and text templates.
- Exactly once per trip (Redis duplicate protection).
- No duplicates after a server restart (in-memory cleared, Redis preserved).
- Evening trip never triggers bus_started or reached_college.
- FCM network failure does not raise or break caller.
"""

import sys
import os
sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))

import asyncio
import time
import pytest
from unittest.mock import MagicMock, patch

from notifications import send_alert
from notification_messages import (
    EVENT_BUS_STARTED,
    EVENT_TWO_STOPS_AWAY,
    EVENT_REACHED_COLLEGE,
    get_channel_info,
    get_notification_content,
)
from routes.tracking import (
    _sync_check_and_notify_parents,
    check_and_notify_parents,
    clear_stops_cache,
    _notified_stops,
)
from tests.test_phase1_simulation import FakeRedis, ROUTE_394_STOPS, setup_mock_supabase


class TestPhase2Notifications:

    def setup_method(self):
        clear_stops_cache()
        _notified_stops.clear()
        self.fake_redis = FakeRedis()

    def test_notification_content_and_channels(self):
        # 1. bus_started
        ch_ta, sound_ta = get_channel_info(EVENT_BUS_STARTED, "ta")
        ch_en, sound_en = get_channel_info(EVENT_BUS_STARTED, "en")
        assert ch_ta == "bus_started_ta_v2"
        assert sound_ta == "bus_started_ta"
        assert ch_en == "bus_started_en_v2"
        assert sound_en == "bus_started_en"

        title_ta, body_ta = get_notification_content(EVENT_BUS_STARTED, "ta", {"bus": "24", "stop": "Tiruvallur"})
        assert title_ta == "பேருந்து 24"
        assert "பேருந்து Tiruvallur நிறுத்தத்திலிருந்து புறப்பட்டது." == body_ta

        title_en, body_en = get_notification_content(EVENT_BUS_STARTED, "en", {"bus": "24", "stop": "Tiruvallur"})
        assert title_en == "Bus 24"
        assert "Bus has started from Tiruvallur." == body_en

        # 2. two_stops_away with minutes
        title_ta_near, body_ta_near = get_notification_content(EVENT_TWO_STOPS_AWAY, "ta", {"bus": "24", "stop": "Redhills", "min": 6})
        assert "Redhills நிறுத்தத்திற்கு பேருந்து இன்னும் 2 நிறுத்தங்களில் உள்ளது. சுமார் 6 நிமிடங்களில் வரும்." == body_ta_near

        title_en_near, body_en_near = get_notification_content(EVENT_TWO_STOPS_AWAY, "en", {"bus": "24", "stop": "Redhills", "min": 6})
        assert "Bus is 2 stops away from Redhills. Arriving in about 6 min." == body_en_near

        # 2b. two_stops_away without minutes
        _, body_ta_nomin = get_notification_content(EVENT_TWO_STOPS_AWAY, "ta", {"bus": "24", "stop": "Redhills", "min": None})
        assert "Redhills நிறுத்தத்திற்கு பேருந்து இன்னும் 2 நிறுத்தங்களில் உள்ளது." == body_ta_nomin

        _, body_en_nomin = get_notification_content(EVENT_TWO_STOPS_AWAY, "en", {"bus": "24", "stop": "Redhills", "min": None})
        assert "Bus is 2 stops away from Redhills." == body_en_nomin

        # 3. reached_college
        ch_arr_ta, sound_arr_ta = get_channel_info(EVENT_REACHED_COLLEGE, "ta")
        assert ch_arr_ta == "bus_arrived_ta_v2"
        assert sound_arr_ta == "bus_arrived_ta"

        _, body_ta_arr = get_notification_content(EVENT_REACHED_COLLEGE, "ta", {"bus": "24", "college": "RMKCET"})
        assert "பேருந்து RMKCET அடைந்தது." == body_ta_arr

        _, body_en_arr = get_notification_content(EVENT_REACHED_COLLEGE, "en", {"bus": "24", "college": "RMKCET"})
        assert "Bus has reached RMKCET." == body_en_arr

    @patch("notifications._get_firebase_app")
    @patch("notifications.messaging.send")
    def test_send_alert_topics_and_structure(self, mock_send, mock_fb_app):
        mock_send.return_value = "msg_id_123"

        # Test two_stops_away sending
        res = send_alert(
            event=EVENT_TWO_STOPS_AWAY,
            bus_id="bus-99",
            stop_id="stop-10",
            variables={"bus": "99", "stop": "Redhills", "min": 5},
        )

        # 2 language topics + 1 legacy topic
        assert "ta" in res
        assert "en" in res
        assert mock_send.call_count >= 2

        # Verify arguments passed to messaging.send
        sent_messages = [call.args[0] for call in mock_send.call_args_list]
        topics = [m.topic for m in sent_messages]

        assert "bus_bus-99_stop_stop-10_ta" in topics
        assert "bus_bus-99_stop_stop-10_en" in topics

        # Verify android notification options (channel_id, high priority)
        ta_msg = next(m for m in sent_messages if m.topic == "bus_bus-99_stop_stop-10_ta")
        assert ta_msg.android.notification.channel_id == "bus_near_ta_v2"
        assert ta_msg.android.notification.sound == "bus_near_ta"
        assert ta_msg.android.priority == "high"
        assert ta_msg.data["event"] == "two_stops_away"
        assert ta_msg.data["bus_id"] == "bus-99"

    @patch("notifications._get_firebase_app")
    @patch("notifications.messaging.send")
    def test_full_trip_events_fired_exactly_once(self, mock_send, mock_fb_app):
        """Simulate morning trip: exactly one bus_started, one two_stops_away per stop, one reached_college."""
        mock_send.return_value = "msg_ok"
        bus_id = "bus-trip-test"
        mock_sb = setup_mock_supabase(ROUTE_394_STOPS, bus_id=bus_id)

        with patch("routes.tracking.supabase", mock_sb), \
             patch("routes.tracking.redis_client", self.fake_redis), \
             patch("services.broadcast.redis_client", self.fake_redis):

            self.fake_redis.set(f"bus:{bus_id}:trip_direction", "morning")

            now = time.time()
            first_stop = ROUTE_394_STOPS[0]
            final_stop = ROUTE_394_STOPS[-1]

            # 1. Bus at depot / first stop (13.140416, 79.908266)
            self.fake_redis.hset(f"bus:{bus_id}", mapping={
                "latitude": first_stop["latitude"],
                "longitude": first_stop["longitude"],
                "speed": 0.0,
                "updated_at": now,
            })
            _sync_check_and_notify_parents(bus_id)

            # bus_started should NOT fire yet while bus is still at the stop (<= 150m)
            # but was_at_first_stop should be recorded
            assert self.fake_redis.get(f"bus:{bus_id}:was_at_first_stop") == "1"

            # 2. Bus moves 400m away from first stop -> bus_started MUST fire
            self.fake_redis.hset(f"bus:{bus_id}", mapping={
                "latitude": first_stop["latitude"] + 0.0035,
                "longitude": first_stop["longitude"] + 0.0035,
                "speed": 30.0,
                "updated_at": now + 10,
            })
            _sync_check_and_notify_parents(bus_id)

            sent_topics = [call.args[0].topic for call in mock_send.call_args_list if hasattr(call.args[0], "topic")]
            assert f"bus_{bus_id}_all_ta" in sent_topics
            assert f"bus_{bus_id}_all_en" in sent_topics

            send_count_after_started = mock_send.call_count

            # 3. Repeat position update 10 times -> bus_started MUST NOT fire again
            for i in range(10):
                self.fake_redis.hset(f"bus:{bus_id}", mapping={
                    "latitude": first_stop["latitude"] + 0.004 + (i * 0.001),
                    "longitude": first_stop["longitude"] + 0.004 + (i * 0.001),
                    "speed": 35.0,
                    "updated_at": now + 20 + i,
                })
                _sync_check_and_notify_parents(bus_id)

            # Assert started event was not duplicated
            started_calls = [
                c for c in mock_send.call_args_list
                if hasattr(c.args[0], "data") and c.args[0].data and c.args[0].data.get("event") == "bus_started"
            ]
            # 2 calls: 1 for ta, 1 for en
            assert len(started_calls) == 2

            # 4. Bus arrives at final stop (RMKCET) -> reached_college MUST fire once
            self.fake_redis.hset(f"bus:{bus_id}", mapping={
                "latitude": final_stop["latitude"],
                "longitude": final_stop["longitude"],
                "speed": 10.0,
                "updated_at": now + 100,
            })
            _sync_check_and_notify_parents(bus_id)

            arrived_calls = [
                c for c in mock_send.call_args_list
                if hasattr(c.args[0], "data") and c.args[0].data and c.args[0].data.get("event") == "reached_college"
            ]
            assert len(arrived_calls) == 2  # ta and en

            # 5. Subsequent update at final stop must not re-send reached_college
            _sync_check_and_notify_parents(bus_id)
            arrived_calls_after = [
                c for c in mock_send.call_args_list
                if hasattr(c.args[0], "data") and c.args[0].data and c.args[0].data.get("event") == "reached_college"
            ]
            assert len(arrived_calls_after) == 2

    @patch("notifications._get_firebase_app")
    @patch("notifications.messaging.send")
    def test_no_duplicates_after_server_restart(self, mock_send, mock_fb_app):
        """Simulate server restart (cleared in-memory cache) with persistent Redis."""
        mock_send.return_value = "msg_ok"
        bus_id = "bus-restart-test"
        mock_sb = setup_mock_supabase(ROUTE_394_STOPS, bus_id=bus_id)

        with patch("routes.tracking.supabase", mock_sb), \
             patch("routes.tracking.redis_client", self.fake_redis), \
             patch("services.broadcast.redis_client", self.fake_redis):

            self.fake_redis.set(f"bus:{bus_id}:trip_direction", "morning")
            first_stop = ROUTE_394_STOPS[0]

            # Mark bus_started already fired in Redis
            today = "2026-10-31"
            self.fake_redis.set(f"notif:started:{bus_id}:{today}", "1")

            # Simulate fresh server restart: clear memory tracker
            _notified_stops.clear()
            clear_stops_cache()

            # Bus is moving
            self.fake_redis.hset(f"bus:{bus_id}", mapping={
                "latitude": first_stop["latitude"] + 0.005,
                "longitude": first_stop["longitude"] + 0.005,
                "speed": 30.0,
                "updated_at": time.time(),
            })

            with patch("routes.tracking.datetime") as mock_dt:
                mock_dt.now.return_value.strftime.return_value = today
                _sync_check_and_notify_parents(bus_id)

            started_calls = [
                c for c in mock_send.call_args_list
                if hasattr(c.args[0], "data") and c.args[0].data and c.args[0].data.get("event") == "bus_started"
            ]
            assert len(started_calls) == 0, "Server restart must not re-fire bus_started when Redis key exists"

    @patch("notifications._get_firebase_app")
    @patch("notifications.messaging.send")
    def test_evening_trip_never_fires_started_or_reached_college(self, mock_send, mock_fb_app):
        """Evening trips must never fire bus_started or reached_college."""
        mock_send.return_value = "msg_ok"
        bus_id = "bus-evening-test"
        mock_sb = setup_mock_supabase(ROUTE_394_STOPS, bus_id=bus_id)

        with patch("routes.tracking.supabase", mock_sb), \
             patch("routes.tracking.redis_client", self.fake_redis), \
             patch("services.broadcast.redis_client", self.fake_redis):

            self.fake_redis.set(f"bus:{bus_id}:trip_direction", "evening")
            first_stop = ROUTE_394_STOPS[0]
            final_stop = ROUTE_394_STOPS[-1]
            now = time.time()

            # 1. Near first stop
            self.fake_redis.hset(f"bus:{bus_id}", mapping={
                "latitude": first_stop["latitude"] + 0.005,
                "longitude": first_stop["longitude"] + 0.005,
                "speed": 35.0,
                "updated_at": now,
            })
            _sync_check_and_notify_parents(bus_id)

            # 2. Near final stop
            self.fake_redis.hset(f"bus:{bus_id}", mapping={
                "latitude": final_stop["latitude"],
                "longitude": final_stop["longitude"],
                "speed": 10.0,
                "updated_at": now + 50,
            })
            _sync_check_and_notify_parents(bus_id)

            forbidden_calls = [
                c for c in mock_send.call_args_list
                if hasattr(c.args[0], "data") and c.args[0].data and c.args[0].data.get("event") in ("bus_started", "reached_college")
            ]
            assert len(forbidden_calls) == 0, "Evening trip must never fire bus_started or reached_college"

    @patch("notifications._get_firebase_app")
    @patch("notifications.messaging.send")
    def test_send_failure_does_not_raise(self, mock_send, mock_fb_app):
        """FCM network exceptions must be caught and never break the GPS ingest thread."""
        mock_send.side_effect = Exception("FCM 503 Service Unavailable")

        # Must return error dict and NOT raise
        res = send_alert(
            event=EVENT_BUS_STARTED,
            bus_id="bus-err-test",
            variables={"bus": "12", "stop": "Tiruvallur"},
        )
        assert res.get("ta") is None
        assert res.get("en") is None
