import os
import requests
from dotenv import load_dotenv

load_dotenv()

supabase_url = os.getenv("SUPABASE_URL")
supabase_key = os.getenv("SUPABASE_KEY")

headers = {
    "apikey": supabase_key,
    "Authorization": f"Bearer {supabase_key}",
    "Content-Type": "application/json"
}

# Test calling REST OpenAPI schema definition to see existing tables and columns
res = requests.get(f"{supabase_url}/rest/v1/", headers=headers)
print("REST API OpenAPI Schema Status:", res.status_code)
if res.status_code == 200:
    data = res.json()
    definitions = data.get("definitions", {})
    print("Routes schema properties:", list(definitions.get("routes", {}).get("properties", {}).keys()))
    print("Buses schema properties:", list(definitions.get("buses", {}).get("properties", {}).keys()))
