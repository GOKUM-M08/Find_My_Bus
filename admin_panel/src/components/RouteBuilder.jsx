import { useState } from 'react'

const BACKEND_URL = window.location.hostname === 'localhost' ? 'http://localhost:8000' : ''
const PRIMARY_BLUE = '#0052CC'
const LIGHT_BLUE = '#E8F0FE'

export default function RouteBuilder({ buses }) {
  const [selectedBus, setSelectedBus] = useState('')
  const [routeName, setRouteName] = useState('')
  const [stops, setStops] = useState([])
  
  // Route Road Condition Parameters (Task 6 Merged Flow)
  const [trafficLevel, setTrafficLevel] = useState('medium')
  const [roadQuality, setRoadQuality] = useState('moderate')
  const [speedBreakers, setSpeedBreakers] = useState('')
  const [narrowSections, setNarrowSections] = useState('')
  const [avgSpeed, setAvgSpeed] = useState('')
  const [peakWindow, setPeakWindow] = useState('')

  const [loading, setLoading] = useState(false)
  const [success, setSuccess] = useState(false)
  const [error, setError] = useState(null)

  const addStop = () => {
    setStops(prev => [
      ...prev,
      { stop_name: '', latitude: '', longitude: '', expected_time: '' }
    ])
  }

  const updateStop = (index, key, value) => {
    setStops(prev => prev.map((s, i) => i === index ? { ...s, [key]: value } : s))
  }

  const removeStop = (index) => {
    setStops(prev => prev.filter((_, i) => i !== index))
  }

  const handleSubmit = async () => {
    setError(null)
    if (!selectedBus || !routeName.trim() || stops.length === 0) {
      setError('Please select a bus, enter a route name, and add at least one stop.')
      return
    }

    const bus = buses.find(b => b.id === selectedBus)
    setLoading(true)
    try {
      // 1. Create Route + Stops
      const routeRes = await fetch(`${BACKEND_URL}/api/buses/route`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          bus_id: selectedBus,
          school_id: bus?.school_id,
          route_name: routeName,
          stops: stops.map(s => ({
            stop_name: s.stop_name,
            latitude: parseFloat(s.latitude) || 0,
            longitude: parseFloat(s.longitude) || 0,
            expected_time: s.expected_time,
          })),
        }),
      })

      if (!routeRes.ok) {
        throw new Error(`Failed to create route (${routeRes.status})`)
      }

      const routeData = await routeRes.json()
      const createdRouteId = routeData.route_id

      // 2. If route condition parameters are filled, save them to the same route (Task 6 Merged Flow)
      if (createdRouteId && createdRouteId !== 'dummy') {
        await fetch(`${BACKEND_URL}/admin/routes/${createdRouteId}/condition`, {
          method: 'PUT',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({
            traffic_level: trafficLevel,
            road_quality: roadQuality,
            num_speed_breakers: speedBreakers ? parseInt(speedBreakers, 10) : null,
            num_narrow_road_sections: narrowSections ? parseInt(narrowSections, 10) : null,
            avg_speed_kmph: avgSpeed ? parseFloat(avgSpeed) : null,
            peak_congestion_window: peakWindow || null,
          }),
        })
      }

      setSuccess(true)
      setRouteName('')
      setStops([])
      setSpeedBreakers('')
      setNarrowSections('')
      setAvgSpeed('')
      setPeakWindow('')
      setTimeout(() => setSuccess(false), 3000)
    } catch (e) {
      setError(e.message)
    } finally {
      setLoading(false)
    }
  }

  return (
    <div style={{ padding: '24px 16px', maxWidth: 740, width: '100%', background: '#F7F9FC', minHeight: '100vh', boxSizing: 'border-box' }}>
      <div style={{ marginBottom: 24 }}>
        <h2 style={{ margin: '0 0 6px', color: '#0F172A', fontSize: 20, fontWeight: 700 }}>
          📍 Route Builder & Condition Manager
        </h2>
        <p style={{ color: '#64748B', margin: 0, fontSize: 13 }}>
          Define pickup routes, ordered GPS stops, and road condition metrics in one unified workflow.
        </p>
      </div>

      {success && (
        <div style={{
          background: '#DCFCE7', color: '#166534',
          padding: '14px 16px', borderRadius: 10, marginBottom: 20,
          border: '1px solid #BBF7D0', fontSize: 14, fontWeight: 600
        }}>
          ✅ Route and condition parameters saved successfully!
        </div>
      )}

      {error && (
        <div style={{
          background: '#FEE2E2', color: '#991B1B',
          padding: '14px 16px', borderRadius: 10, marginBottom: 20,
          border: '1px solid #FECACA', fontSize: 14, fontWeight: 600
        }}>
          ⚠️ {error}
        </div>
      )}

      <div style={{ background: 'white', padding: '24px 16px', borderRadius: 12, border: '1px solid #E2E8F0', boxShadow: '0 4px 12px rgba(0,82,204,0.04)', boxSizing: 'border-box' }}>
        <div style={{ marginBottom: 20 }}>
          <label style={{ display: 'block', marginBottom: 6, fontWeight: 600, fontSize: 14, color: '#0F172A' }}>
            🚌 Select Bus *
          </label>
          <select
            value={selectedBus}
            onChange={e => setSelectedBus(e.target.value)}
            style={{ width: '100%', padding: '12px 14px', border: '1px solid #E2E8F0',
                     borderRadius: 8, fontSize: 14, boxSizing: 'border-box', outline: 'none', cursor: 'pointer' }}>
            <option value=''>Select Bus Vehicle</option>
            {buses.map(b => (
              <option key={b.id} value={b.id}>{b.bus_number} ({b.driver_name || 'No driver'})</option>
            ))}
          </select>
        </div>

        <div style={{ marginBottom: 24 }}>
          <label style={{ display: 'block', marginBottom: 6, fontWeight: 600, fontSize: 14, color: '#0F172A' }}>
            Route Name *
          </label>
          <input
            type="text"
            value={routeName}
            onChange={e => setRouteName(e.target.value)}
            placeholder="e.g. Morning Pickup — North Zone"
            style={{ width: '100%', padding: '12px 14px', border: '1px solid #E2E8F0',
                     borderRadius: 8, fontSize: 14, boxSizing: 'border-box', outline: 'none' }}
          />
        </div>

        {/* Integrated Road Condition Parameters Section */}
        <div style={{
          background: '#F8FAFC', border: '1px solid #E2E8F0',
          borderRadius: 10, padding: 16, marginBottom: 24, boxSizing: 'border-box'
        }}>
          <h4 style={{ margin: '0 0 14px', fontSize: 14, color: '#0F172A', fontWeight: 700 }}>
            🚦 Road Condition & Traffic Parameters
          </h4>
          <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit, minmax(200px, 1fr))', gap: 14, marginBottom: 14 }}>
            <div>
              <label style={{ display: 'block', marginBottom: 4, fontSize: 13, fontWeight: 600, color: '#475569' }}>
                Traffic Congestion Level
              </label>
              <select
                value={trafficLevel}
                onChange={e => setTrafficLevel(e.target.value)}
                style={{ width: '100%', padding: '10px 12px', border: '1px solid #CBD5E1', borderRadius: 6, fontSize: 13, boxSizing: 'border-box' }}>
                <option value="low">Low Traffic</option>
                <option value="medium">Medium Traffic</option>
                <option value="high">High Traffic</option>
              </select>
            </div>

            <div>
              <label style={{ display: 'block', marginBottom: 4, fontSize: 13, fontWeight: 600, color: '#475569' }}>
                Overall Road Quality
              </label>
              <select
                value={roadQuality}
                onChange={e => setRoadQuality(e.target.value)}
                style={{ width: '100%', padding: '10px 12px', border: '1px solid #CBD5E1', borderRadius: 6, fontSize: 13, boxSizing: 'border-box' }}>
                <option value="good">Good (Smooth Pavement)</option>
                <option value="moderate">Moderate</option>
                <option value="poor">Poor (Potholes / Unpaved)</option>
              </select>
            </div>
          </div>

          <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit, minmax(200px, 1fr))', gap: 14 }}>
            <div>
              <label style={{ display: 'block', marginBottom: 4, fontSize: 13, fontWeight: 600, color: '#475569' }}>
                Speed Breakers Count
              </label>
              <input
                type="number"
                placeholder="e.g. 4"
                value={speedBreakers}
                onChange={e => setSpeedBreakers(e.target.value)}
                style={{ width: '100%', padding: '10px 12px', border: '1px solid #CBD5E1', borderRadius: 6, fontSize: 13, boxSizing: 'border-box' }}
              />
            </div>

            <div>
              <label style={{ display: 'block', marginBottom: 4, fontSize: 13, fontWeight: 600, color: '#475569' }}>
                Narrow Road Sections
              </label>
              <input
                type="number"
                placeholder="e.g. 2"
                value={narrowSections}
                onChange={e => setNarrowSections(e.target.value)}
                style={{ width: '100%', padding: '10px 12px', border: '1px solid #CBD5E1', borderRadius: 6, fontSize: 13, boxSizing: 'border-box' }}
              />
            </div>
          </div>
        </div>

        {/* Ordered Stops Section */}
        <h3 style={{ marginTop: 0, marginBottom: 16, fontSize: 15, fontWeight: 700, color: '#0F172A' }}>
          🏁 Ordered Route Stops *
        </h3>

        {stops.map((stop, i) => (
          <div key={i} style={{
            border: `1px solid ${LIGHT_BLUE}`, borderRadius: 10,
            padding: 18, marginBottom: 14, position: 'relative',
            background: '#F8FAFC'
          }}>
            <span style={{
              position: 'absolute', top: -12, left: 16, background: PRIMARY_BLUE,
              color: 'white', padding: '2px 8px', fontSize: 11,
              fontWeight: 700, borderRadius: 4
            }}>
              Stop {i + 1}
            </span>
            <input
              placeholder="Stop Name (e.g. Central Gate A)"
              value={stop.stop_name}
              onChange={e => updateStop(i, 'stop_name', e.target.value)}
              style={{ width: '100%', padding: '10px 12px', marginBottom: 10,
                       border: '1px solid #E2E8F0', borderRadius: 6, boxSizing: 'border-box',
                       fontSize: 14 }}
            />
            <div style={{ display: 'flex', gap: 10, marginBottom: 10 }}>
              <input
                placeholder="Latitude (e.g. 13.0827)"
                value={stop.latitude}
                onChange={e => updateStop(i, 'latitude', e.target.value)}
                type="number"
                step="0.0001"
                style={{ flex: 1, padding: '10px 12px', border: '1px solid #E2E8F0',
                         borderRadius: 6, boxSizing: 'border-box', fontSize: 14 }}
              />
              <input
                placeholder="Longitude (e.g. 80.2707)"
                value={stop.longitude}
                onChange={e => updateStop(i, 'longitude', e.target.value)}
                type="number"
                step="0.0001"
                style={{ flex: 1, padding: '10px 12px', border: '1px solid #E2E8F0',
                         borderRadius: 6, boxSizing: 'border-box', fontSize: 14 }}
              />
            </div>
            <div style={{ display: 'flex', gap: 10 }}>
              <input
                placeholder="Expected Arrival (e.g. 07:15 AM)"
                value={stop.expected_time}
                onChange={e => updateStop(i, 'expected_time', e.target.value)}
                style={{ flex: 1, padding: '10px 12px', border: '1px solid #E2E8F0',
                         borderRadius: 6, boxSizing: 'border-box', fontSize: 14 }}
              />
              <button
                onClick={() => removeStop(i)}
                style={{ background: '#FEE2E2', color: '#991B1B', border: '1px solid #FECACA',
                         borderRadius: 6, padding: '0 14px', cursor: 'pointer',
                         fontWeight: 600 }}>
                ✕ Remove
              </button>
            </div>
          </div>
        ))}

        <button
          onClick={addStop}
          style={{
            background: LIGHT_BLUE, color: PRIMARY_BLUE, border: `1px solid ${PRIMARY_BLUE}`,
            padding: '12px 16px', borderRadius: 8, cursor: 'pointer',
            width: '100%', marginBottom: 20, fontWeight: 600,
            transition: 'all 0.2s'
          }}>
          + Add Stop
        </button>

        <button
          onClick={handleSubmit}
          disabled={loading || !selectedBus || !routeName.trim() || stops.length === 0}
          style={{
            background: loading || !selectedBus || !routeName.trim() || stops.length === 0 ? '#94A3B8' : PRIMARY_BLUE,
            color: 'white', border: 'none',
            padding: '14px 32px', borderRadius: 8, fontSize: 15,
            cursor: loading || !selectedBus || !routeName.trim() || stops.length === 0 ? 'not-allowed' : 'pointer',
            width: '100%', fontWeight: 600, transition: 'all 0.2s'
          }}>
          {loading ? 'Saving Route...' : '💾 Save Route & Conditions'}
        </button>
      </div>
    </div>
  )
}
