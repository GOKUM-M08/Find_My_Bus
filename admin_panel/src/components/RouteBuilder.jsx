// NOTE: App.jsx imports this component ("Build Route" tab) and the
// guide's folder structure lists it, but its contents are never
// written out anywhere in the guide. This is a working implementation
// that POSTs to the /api/buses/route endpoint defined in
// backend/routes/buses.py (see create_route()), letting an admin pick
// a bus, name a route, and add ordered stops with lat/lng + expected time.

import { useState } from 'react'

const BACKEND_URL = 'http://localhost:8000'

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
    <div style={{ padding: 40, maxWidth: 600 }}>
      <h2 style={{ marginBottom: 24 }}>Build Route</h2>

      {success && (
        <div style={{
          background: '#dcfce7', color: '#166534',
          padding: '12px 16px', borderRadius: 8, marginBottom: 20
        }}>
          ✅ Route created successfully!
        </div>
      )}

      <div style={{ marginBottom: 16 }}>
        <label style={{ display: 'block', marginBottom: 6, fontWeight: 600, fontSize: 14 }}>
          Bus
        </label>
        <select
          value={selectedBus}
          onChange={e => setSelectedBus(e.target.value)}
          style={{ width: '100%', padding: '10px 14px', border: '1px solid #ddd',
                   borderRadius: 8, fontSize: 15, boxSizing: 'border-box' }}>
          <option value=''>Select Bus</option>
          {buses.map(b => (
            <option key={b.id} value={b.id}>{b.bus_number}</option>
          ))}
        </select>
      </div>

      <div style={{ marginBottom: 16 }}>
        <label style={{ display: 'block', marginBottom: 6, fontWeight: 600, fontSize: 14 }}>
          Route Name
        </label>
        <input
          type="text"
          value={routeName}
          onChange={e => setRouteName(e.target.value)}
          placeholder="e.g. Morning Pickup — North Zone"
          style={{ width: '100%', padding: '10px 14px', border: '1px solid #ddd',
                   borderRadius: 8, fontSize: 15, boxSizing: 'border-box' }}
        />
      </div>

      <h3 style={{ marginTop: 28, marginBottom: 12, fontSize: 15 }}>
        Stops (in order)
      </h3>

      {stops.map((stop, i) => (
        <div key={i} style={{
          border: '1px solid #E2E8F0', borderRadius: 8,
          padding: 14, marginBottom: 12, position: 'relative'
        }}>
          <span style={{
            position: 'absolute', top: -10, left: 12, background: 'white',
            padding: '0 6px', fontSize: 12, color: '#64748B', fontWeight: 600
          }}>
            Stop {i + 1}
          </span>
          <input
            placeholder="Stop name"
            value={stop.stop_name}
            onChange={e => updateStop(i, 'stop_name', e.target.value)}
            style={{ width: '100%', padding: '8px 10px', marginBottom: 8,
                     border: '1px solid #ddd', borderRadius: 6, boxSizing: 'border-box' }}
          />
          <div style={{ display: 'flex', gap: 8, marginBottom: 8 }}>
            <input
              placeholder="Latitude"
              value={stop.latitude}
              onChange={e => updateStop(i, 'latitude', e.target.value)}
              style={{ flex: 1, padding: '8px 10px', border: '1px solid #ddd',
                       borderRadius: 6, boxSizing: 'border-box' }}
            />
            <input
              placeholder="Longitude"
              value={stop.longitude}
              onChange={e => updateStop(i, 'longitude', e.target.value)}
              style={{ flex: 1, padding: '8px 10px', border: '1px solid #ddd',
                       borderRadius: 6, boxSizing: 'border-box' }}
            />
          </div>
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
