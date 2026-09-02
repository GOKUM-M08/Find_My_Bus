"""
One-off test helper: manually writes a bus location into Redis,
the same way gps_listener.py normally does before it POSTs to
/internal/broadcast. Needed because testing via the Supabase SQL
editor or a raw curl to /internal/broadcast skips this step,
which makes get_eta() (and therefore check_and_notify_parents)
always see "no data" and silently do nothing.

Run from inside the backend/ folder:
    python test_redis_push.py
"""
from database import redis_client

BUS_ID = "32d67973-8738-4d13-b012-a9c73b4b76e7"

redis_client.hset(f"bus:{BUS_ID}", mapping={
    "latitude": 13.309097,
    "longitude": 80.04552,
    "speed": 20,
})
redis_client.expire(f"bus:{BUS_ID}", 3600)

print(f"Redis updated for bus:{BUS_ID}")
