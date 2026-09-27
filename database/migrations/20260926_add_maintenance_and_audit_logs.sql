-- Migration for Bus Maintenance Tracking, Admin Action Audit Logs, and Overspeed Logs

-- 1. Add maintenance and fuel columns to buses table if missing
ALTER TABLE buses
  ADD COLUMN IF NOT EXISTS last_service_date DATE,
  ADD COLUMN IF NOT EXISTS next_service_due_date DATE,
  ADD COLUMN IF NOT EXISTS next_service_due_km DOUBLE PRECISION,
  ADD COLUMN IF NOT EXISTS current_odometer_km DOUBLE PRECISION DEFAULT 0.0,
  ADD COLUMN IF NOT EXISTS diesel_tank_capacity DOUBLE PRECISION DEFAULT 100.0;

-- 2. Create admin_audit_logs table for audit trail
CREATE TABLE IF NOT EXISTS admin_audit_logs (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  school_id UUID REFERENCES schools(id),
  admin_user_id TEXT,
  admin_email TEXT,
  action_type TEXT NOT NULL,
  target_entity TEXT NOT NULL,
  target_id TEXT,
  details TEXT,
  created_at TIMESTAMP DEFAULT NOW()
);

-- Enable RLS on admin_audit_logs
ALTER TABLE admin_audit_logs ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Allow read admin_audit_logs" ON admin_audit_logs FOR SELECT USING (true);
CREATE POLICY "Service full access admin_audit_logs" ON admin_audit_logs USING (true);

-- 3. Create overspeed_logs table for logging > 60 km/h events
CREATE TABLE IF NOT EXISTS overspeed_logs (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  bus_id UUID REFERENCES buses(id),
  speed DOUBLE PRECISION NOT NULL,
  latitude DOUBLE PRECISION,
  longitude DOUBLE PRECISION,
  recorded_at TIMESTAMP DEFAULT NOW()
);

-- Enable RLS on overspeed_logs
ALTER TABLE overspeed_logs ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Allow read overspeed_logs" ON overspeed_logs FOR SELECT USING (true);
CREATE POLICY "Service full access overspeed_logs" ON overspeed_logs USING (true);
