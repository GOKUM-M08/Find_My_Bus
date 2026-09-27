-- Migration for AI Route Condition Scoring, Sharp Turns, and Monthly Analytics Snapshots

-- 1. Add route condition columns to routes table
ALTER TABLE routes
  ADD COLUMN IF NOT EXISTS speed_breaker_count INTEGER DEFAULT 0,
  ADD COLUMN IF NOT EXISTS sharp_turn_count INTEGER DEFAULT 0,
  ADD COLUMN IF NOT EXISTS traffic_level TEXT CHECK (traffic_level IN ('low', 'medium', 'high')) DEFAULT 'medium',
  ADD COLUMN IF NOT EXISTS road_quality TEXT CHECK (road_quality IN ('good', 'average', 'moderate', 'poor')) DEFAULT 'average';

-- Ensure default values for speed_breaker_count
UPDATE routes 
SET speed_breaker_count = 0 
WHERE speed_breaker_count IS NULL;

-- 2. Create monthly_analytics_snapshots table for continuous monthly training pipeline
CREATE TABLE IF NOT EXISTS monthly_analytics_snapshots (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  school_id UUID REFERENCES schools(id),
  snapshot_month DATE NOT NULL,
  total_trips INTEGER DEFAULT 0,
  total_gps_distance_km DOUBLE PRECISION DEFAULT 0.0,
  total_diesel_liters DOUBLE PRECISION DEFAULT 0.0,
  avg_fleet_efficiency_kmpl DOUBLE PRECISION DEFAULT 0.0,
  overspeed_event_count INTEGER DEFAULT 0,
  maintenance_event_count INTEGER DEFAULT 0,
  raw_telemetry_json JSONB,
  created_at TIMESTAMP DEFAULT NOW()
);

-- Enable RLS on monthly_analytics_snapshots
ALTER TABLE monthly_analytics_snapshots ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Allow read monthly_analytics_snapshots" ON monthly_analytics_snapshots FOR SELECT USING (true);
CREATE POLICY "Service full access monthly_analytics_snapshots" ON monthly_analytics_snapshots USING (true);
