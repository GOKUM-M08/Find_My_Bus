import os
import sys
import psycopg2
from dotenv import load_dotenv

load_dotenv()

# Common Supabase connection parameters
project_ref = "mardeektaxigbxlckwzv"
supabase_url = os.getenv("SUPABASE_URL", "")
supabase_key = os.getenv("SUPABASE_KEY", "")

# Try possible database hosts
hosts = [
    f"db.{project_ref}.supabase.co",
    f"aws-0-ap-south-1.pooler.supabase.com",
    "localhost"
]

db_password = os.getenv("SUPABASE_DB_PASSWORD") or os.getenv("POSTGRES_PASSWORD")

print("Checking DB connection...")
connected = False
for host in hosts:
    if not db_password:
        break
    try:
        conn = psycopg2.connect(
            host=host,
            port=5432 if "db." in host else 6543,
            user="postgres" if "db." in host else f"postgres.{project_ref}",
            password=db_password,
            dbname="postgres"
        )
        print(f"Successfully connected to {host}!")
        cursor = conn.cursor()
        with open("database/migrations/20260903_add_phase1_route_optimizer_columns.sql", "r") as f:
            sql = f.read()
        cursor.execute(sql)
        conn.commit()
        print("Migration executed successfully via psycopg2!")
        connected = True
        conn.close()
        break
    except Exception as e:
        print(f"Failed to connect to {host}: {e}")

if not connected:
    print("Could not connect via raw postgres TCP. Writing fallback migration verification...")
