import os
from supabase import create_client, Client
from redis import Redis
from dotenv import load_dotenv

load_dotenv()

# Supabase connection
supabase: Client = create_client(
    os.getenv("SUPABASE_URL"),
    os.getenv("SUPABASE_KEY")
)

# Redis (Upstash) connection
redis_client = Redis(
    host=os.getenv("UPSTASH_REDIS_HOST"),
    port=int(os.getenv("UPSTASH_REDIS_PORT", 6379)),
    password=os.getenv("UPSTASH_REDIS_TOKEN"),
    ssl=True,
    decode_responses=True
)