import { useState } from 'react'

// Same pattern as RouteBuilder.jsx: writes go through the backend
// (which uses the secret service_role key) instead of straight to
// Supabase from the browser, since buses' RLS policy only allows
// service_role to insert. Point this at localhost while testing,
// and swap it for your real Render URL in Phase 9.
const BACKEND_URL = 'http://localhost:8000'
const PRIMARY_BLUE = '#0052CC'
const LIGHT_BLUE = '#E8F0FE'

export default function AddBus({ schoolId, onAdded }) {
  const [form, setForm] = useState({
    bus_number: '', bus_code: '', driver_name: '',
    driver_phone: '', device_id: '', capacity: 40
  })
  const [loading, setLoading] = useState(false)
  const [success, setSuccess] = useState(false)

  const handleSubmit = async () => {
    if (!form.bus_number || !form.device_id) {
      alert('Bus number and Device ID are required!')
      return
    }
    setLoading(true)
    try {
      const response = await fetch(`${BACKEND_URL}/api/buses/`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          ...form,
          capacity: Number(form.capacity),
          school_id: schoolId
        })
      })
      if (!response.ok) {
        const err = await response.json().catch(() => ({}))
        throw new Error(err.detail ? JSON.stringify(err.detail) : `Request failed (${response.status})`)
      }
      setSuccess(true)
      setForm({ bus_number: '', bus_code: '', driver_name: '',
                 driver_phone: '', device_id: '', capacity: 40 })
      onAdded()
      setTimeout(() => setSuccess(false), 3000)
    } catch (error) {
      alert('Error: ' + error.message)
    } finally {
      setLoading(false)
    }
  }

  const field = (label, key, type = 'text') => (
    <div style={{ marginBottom: 18 }}>
      <label style={{ display: 'block', marginBottom: 8,
                      fontWeight: 600, fontSize: 14, color: '#333' }}>{label}</label>
      <input
        type={type}
        value={form[key]}
        onChange={e => setForm(p => ({ ...p, [key]: e.target.value }))}
        style={{
          width: '100%', padding: '12px 14px', border: `2px solid #ddd`,
          borderRadius: 8, fontSize: 15, boxSizing: 'border-box',
          transition: 'all 0.3s', outline: 'none',
          ':focus': { borderColor: PRIMARY_BLUE }
        }}
        onFocus={(e) => e.target.style.borderColor = PRIMARY_BLUE}
        onBlur={(e) => e.target.style.borderColor = '#ddd'}
      />
    </div>
  )

  return (
    <div style={{ padding: 40, maxWidth: 600, background: '#F7F9FC', minHeight: '100vh' }}>
      <h2 style={{ marginBottom: 8, color: '#333' }}>🚌 Add New Bus</h2>
      <p style={{ color: '#666', marginBottom: 28, fontSize: 14 }}>Register a new bus in the system</p>
      {success && (
        <div style={{
          background: '#D4EDDA', color: '#155724',
          padding: '14px 16px', borderRadius: 8, marginBottom: 24,
          border: '1px solid #C3E6CB', fontSize: 14
        }}>
          ✅ Bus added successfully!
        </div>
      )}
      
      <div style={{ background: 'white', padding: 32, borderRadius: 12, boxShadow: '0 4px 12px rgba(0,82,204,0.08)' }}>
        {field('Bus Number (e.g. TN09 AB 1234)', 'bus_number')}
        {field('Bus Code (e.g. Bus-A)', 'bus_code')}
        {field('Driver Name', 'driver_name')}
        {field('Driver Phone', 'driver_phone')}
        {field('GPS Device ID (from tracker)', 'device_id')}
        {field('Capacity (students)', 'capacity', 'number')}
        
        <button
          onClick={handleSubmit}
          disabled={loading}
          style={{
            background: loading ? '#9DB3D6' : PRIMARY_BLUE, 
            color: 'white', border: 'none',
            padding: '14px 32px', borderRadius: 8, fontSize: 16,
            cursor: loading ? 'not-allowed' : 'pointer', width: '100%',
            opacity: loading ? 0.7 : 1,
            fontWeight: 600,
            transition: 'all 0.3s',
            marginTop: 12
          }}
          onMouseEnter={(e) => !loading && (e.target.style.background = '#00338C')}
          onMouseLeave={(e) => !loading && (e.target.style.background = PRIMARY_BLUE)}
        >
          {loading ? 'Adding Bus...' : '➕ Add Bus'}
        </button>
      </div>
    </div>
  )
}