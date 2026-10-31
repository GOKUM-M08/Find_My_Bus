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
        def __init__(self):
            self._kv = {}
            self._hash = {}
        def get(self, name):
            return self._kv.get(name)
        def set(self, name, value, ex=None):
            self._kv[name] = str(value)
            return True
        def delete(self, *names):
            count = 0
            for n in names:
                if n in self._kv:
                    del self._kv[n]
                    count += 1
                if n in self._hash:
                    del self._hash[n]
                    count += 1
            return count
        def hgetall(self, name):
            return dict(self._hash.get(name, {}))
        def hset(self, name, key=None, value=None, mapping=None):
            if name not in self._hash:
                self._hash[name] = {}
            if mapping:
                for k, v in mapping.items():
                    self._hash[name][str(k)] = str(v)
            if key is not None and value is not None:
                self._hash[name][str(key)] = str(value)
            return True
        def expire(self, name, time):
            return True
    redis_client = DummyRedis()