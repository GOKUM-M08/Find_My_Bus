import os
import requests
from dotenv import load_dotenv

load_dotenv()

supabase_url = os.getenv("SUPABASE_URL")
supabase_key = os.getenv("SUPABASE_KEY")

print("Supabase URL:", supabase_url)

headers = {
    "apikey": supabase_key,
    "Authorization": f"Bearer {supabase_key}",
    "Content-Type": "application/json",
}

# Check if pg8000 or psycopg2 or requests to Supabase SQL api works
try:
    import psycopg2
    print("psycopg2 installed")
except ImportError:
    print("psycopg2 NOT installed")
