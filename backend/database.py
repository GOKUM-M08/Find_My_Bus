import os
from supabase import create_client, Client
from redis import Redis
from dotenv import load_dotenv

load_dotenv()

supabase_url = os.getenv("SUPABASE_URL", "https://placeholder.supabase.co")
supabase_key = os.getenv("SUPABASE_KEY", "placeholder")

try:
    supabase: Client = create_client(supabase_url, supabase_key)
except Exception:
    supabase = None

redis_host = os.getenv("UPSTASH_REDIS_HOST")
redis_port = int(os.getenv("UPSTASH_REDIS_PORT", 6379))
redis_token = os.getenv("UPSTASH_REDIS_TOKEN")

if redis_host:
    redis_client = Redis(
        host=redis_host,
        port=redis_port,
        password=redis_token,
        ssl=True,
        decode_responses=True
    )
else:
    class DummyRedis:
        def hgetall(self, name): return {}
        def hset(self, name, mapping=None): pass
        def expire(self, name, time): pass
    redis_client = DummyRedis()