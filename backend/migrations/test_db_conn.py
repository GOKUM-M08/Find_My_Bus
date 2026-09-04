import os
import psycopg2
from dotenv import load_dotenv

load_dotenv()

# Let's test common database connection strings for Supabase project mardeektaxigbxlckwzv
db_host = "db.mardeektaxigbxlckwzv.supabase.co"
# Alternatively pooler host
pooler_host = "aws-0-ap-south-1.pooler.supabase.com"

# Let's try connecting with standard passwords or secret key
db_pass = os.getenv("SUPABASE_DB_PASSWORD") or os.getenv("SUPABASE_KEY")

print("DB Host:", db_host)
