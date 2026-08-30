// NOTE: App.jsx imports this component ("Build Route" tab) and the
// guide's folder structure lists it, but its contents are never
// written out anywhere in the guide. This is a working implementation
// that POSTs to the /api/buses/route endpoint defined in
// backend/routes/buses.py (see create_route()), letting an admin pick
// a bus, name a route, and add ordered stops with lat/lng + expected time.

import { useState } from 'react'

const BACKEND_URL = 'http://localhost:8000'
const PRIMARY_BLUE = '#0052CC'
const LIGHT_BLUE = '#E8F0FE'

export default function RouteBuilder({ buses }) {
  const [selectedBus, setSelectedBus] = useState('')
  const [routeName, setRouteName] = useState('')
  const [stops, setStops] = useState([])
  const [loading, setLoading] = useState(false)
  const [success, setSuccess] = useState(false)

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
    if (!selectedBus || !routeName || stops.length === 0) {
      alert('Pick a bus, name the route, and add at least one stop.')
      return
    }

    const bus = buses.find(b => b.id === selectedBus)
    setLoading(true)
    try {
      const response = await fetch(`${BACKEND_URL}/api/buses/route`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          bus_id: selectedBus,
          school_id: bus?.school_id,
          route_name: routeName,
          stops: stops.map(s => ({
            stop_name: s.stop_name,
            latitude: parseFloat(s.latitude),
            longitude: parseFloat(s.longitude),
            expected_time: s.expected_time,
          })),
        }),
      })
      if (!response.ok) throw new Error('Request failed')
      setSuccess(true)
      setRouteName('')
      setStops([])
      setTimeout(() => setSuccess(false), 3000)
    } catch (e) {
      alert('Error creating route: ' + e.message)
    } finally {
      setLoading(false)
    }
  }

  return (
    <div style={{ padding: 40, maxWidth: 700, background: '#F7F9FC', minHeight: '100vh' }}>
      <h2 style={{ marginBottom: 8, color: '#333' }}>📍 Build Route</h2>
      <p style={{ color: '#666', marginBottom: 28, fontSize: 14 }}>Create pickup routes with ordered stops</p>

      {success && (
        <div style={{
          background: '#D4EDDA', color: '#155724',
          padding: '14px 16px', borderRadius: 8, marginBottom: 24,
          border: '1px solid #C3E6CB', fontSize: 14
        }}>
          ✅ Route created successfully!
        </div>
      )}

      <div style={{ background: 'white', padding: 32, borderRadius: 12, boxShadow: '0 4px 12px rgba(0,82,204,0.08)' }}>
        <div style={{ marginBottom: 20 }}>
          <label style={{ display: 'block', marginBottom: 8, fontWeight: 600, fontSize: 14, color: '#333' }}>
            🚌 Select Bus
          </label>
          <select
            value={selectedBus}
            onChange={e => setSelectedBus(e.target.value)}
            style={{ width: '100%', padding: '12px 14px', border: `2px solid #ddd`,
                     borderRadius: 8, fontSize: 15, boxSizing: 'border-box',
                     transition: 'all 0.3s', outline: 'none', cursor: 'pointer' }}
            onFocus={(e) => e.target.style.borderColor = PRIMARY_BLUE}
            onBlur={(e) => e.target.style.borderColor = '#ddd'}>
            <option value=''>Select Bus</option>
            {buses.map(b => (
              <option key={b.id} value={b.id}>{b.bus_number} - {b.driver_name || 'No Driver'}</option>
            ))}
          </select>
        </div>

        <div style={{ marginBottom: 28 }}>
          <label style={{ display: 'block', marginBottom: 8, fontWeight: 600, fontSize: 14, color: '#333' }}>
            Route Name
          </label>
          <input
            type="text"
            value={routeName}
            onChange={e => setRouteName(e.target.value)}
            placeholder="e.g. Morning Pickup — North Zone"
            style={{ width: '100%', padding: '12px 14px', border: `2px solid #ddd`,
                     borderRadius: 8, fontSize: 15, boxSizing: 'border-box',
                     transition: 'all 0.3s', outline: 'none' }}
            onFocus={(e) => e.target.style.borderColor = PRIMARY_BLUE}
            onBlur={(e) => e.target.style.borderColor = '#ddd'}
          />
        </div>

        <h3 style={{ marginTop: 0, marginBottom: 16, fontSize: 15, fontWeight: 700, color: '#333' }}>
          🏁 Stops (in order)
        </h3>

        {stops.map((stop, i) => (
          <div key={i} style={{
            border: `2px solid ${LIGHT_BLUE}`, borderRadius: 10,
            padding: 18, marginBottom: 14, position: 'relative',
            background: '#F7F9FC'
          }}>
            <span style={{
              position: 'absolute', top: -14, left: 16, background: PRIMARY_BLUE,
              color: 'white', padding: '4px 10px', fontSize: 12, 
              fontWeight: 700, borderRadius: 6
            }}>
              Stop {i + 1}
            </span>
            <input
              placeholder="Stop name (e.g. School Gate A)"
              value={stop.stop_name}
              onChange={e => updateStop(i, 'stop_name', e.target.value)}
              style={{ width: '100%', padding: '10px 12px', marginBottom: 10,
                       border: '1px solid #ddd', borderRadius: 6, boxSizing: 'border-box',
                       fontSize: 14 }}
            />
            <div style={{ display: 'flex', gap: 10, marginBottom: 10 }}>
              <input
                placeholder="Latitude (e.g. 13.0827)"
                value={stop.latitude}
                onChange={e => updateStop(i, 'latitude', e.target.value)}
                type="number"
                step="0.0001"
                style={{ flex: 1, padding: '10px 12px', border: '1px solid #ddd',
                         borderRadius: 6, boxSizing: 'border-box', fontSize: 14 }}
              />
              <input
                placeholder="Longitude (e.g. 80.2707)"
                value={stop.longitude}
                onChange={e => updateStop(i, 'longitude', e.target.value)}
                type="number"
                step="0.0001"
                style={{ flex: 1, padding: '10px 12px', border: '1px solid #ddd',
                         borderRadius: 6, boxSizing: 'border-box', fontSize: 14 }}
              />
            </div>
            <div style={{ display: 'flex', gap: 10 }}>
              <input
                placeholder="Expected time (e.g. 07:15 AM)"
                value={stop.expected_time}
                onChange={e => updateStop(i, 'expected_time', e.target.value)}
                style={{ flex: 1, padding: '10px 12px', border: '1px solid #ddd',
                         borderRadius: 6, boxSizing: 'border-box', fontSize: 14 }}
              />
              <button
                onClick={() => removeStop(i)}
                style={{ background: '#FEE2E2', color: '#991B1B', border: 'none',
                         borderRadius: 6, padding: '0 14px', cursor: 'pointer',
                         fontWeight: 600, transition: 'all 0.3s' }}
                onMouseEnter={(e) => e.target.style.background = '#FECACA'}
                onMouseLeave={(e) => e.target.style.background = '#FEE2E2'}>
                ✕ Remove
              </button>
            </div>
          </div>
        ))}

        <button
          onClick={addStop}
          style={{
            background: LIGHT_BLUE, color: PRIMARY_BLUE, border: `2px solid ${PRIMARY_BLUE}`,
            padding: '12px 16px', borderRadius: 8, cursor: 'pointer',
            width: '100%', marginBottom: 20, fontWeight: 600,
            transition: 'all 0.3s'
          }}
          onMouseEnter={(e) => e.target.style.background = PRIMARY_BLUE && (e.target.style.color = 'white')}
          onMouseLeave={(e) => e.target.style.background = LIGHT_BLUE && (e.target.style.color = PRIMARY_BLUE)}>
          + Add Stop
        </button>

        <button
          onClick={handleSubmit}
          disabled={loading || !selectedBus || !routeName || stops.length === 0}
          style={{
            background: loading || !selectedBus || !routeName || stops.length === 0 ? '#9DB3D6' : PRIMARY_BLUE, 
            color: 'white', border: 'none',
            padding: '14px 32px', borderRadius: 8, fontSize: 16,
            cursor: loading || !selectedBus || !routeName || stops.length === 0 ? 'not-allowed' : 'pointer', 
            width: '100%',
            fontWeight: 600,
            transition: 'all 0.3s'
          }}
          onMouseEnter={(e) => !loading && selectedBus && routeName && stops.length > 0 && (e.target.style.background = '#00338C')}
          onMouseLeave={(e) => !loading && selectedBus && routeName && stops.length > 0 && (e.target.style.background = PRIMARY_BLUE)}>
          {loading ? 'Saving Route...' : '💾 Save Route'}
        </button>
      </div>
    </div>
  )
          <div style={{ display: 'flex', gap: 8 }}>
            <input
              placeholder="Expected time (e.g. 07:15 AM)"
              value={stop.expected_time}
              onChange={e => updateStop(i, 'expected_time', e.target.value)}
              style={{ flex: 1, padding: '8px 10px', border: '1px solid #ddd',
                       borderRadius: 6, boxSizing: 'border-box' }}
            />
            <button
              onClick={() => removeStop(i)}
              style={{ background: '#FEE2E2', color: '#991B1B', border: 'none',
                       borderRadius: 6, padding: '0 14px', cursor: 'pointer' }}>
              Remove
            </button>
          </div>
        </div>
      ))}

      <button
        onClick={addStop}
        style={{
          background: '#F1F5F9', color: '#1E293B', border: '1px dashed #94A3B8',
          padding: '10px 16px', borderRadius: 8, cursor: 'pointer',
          width: '100%', marginBottom: 20
        }}>
        + Add Stop
      </button>

      <button
        onClick={handleSubmit}
        disabled={loading}
        style={{
          background: '#1E6BFF', color: 'white', border: 'none',
          padding: '14px 32px', borderRadius: 8, fontSize: 16,
          cursor: loading ? 'not-allowed' : 'pointer', width: '100%',
          opacity: loading ? 0.7 : 1
        }}>
        {loading ? 'Saving Route...' : 'Save Route'}
      </button>
    </div>
  )
}
