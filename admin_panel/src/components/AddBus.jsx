import { useState } from 'react'

// Same pattern as RouteBuilder.jsx: writes go through the backend
// (which uses the secret service_role key) instead of straight to
// Supabase from the browser, since buses' RLS policy only allows
// service_role to insert. Point this at localhost while testing,
// and swap it for your real Render URL in Phase 9.
const BACKEND_URL = 'http://localhost:8000'

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
    <div style={{ marginBottom: 16 }}>
      <label style={{ display: 'block', marginBottom: 6,
                      fontWeight: 600, fontSize: 14 }}>{label}</label>
      <input
        type={type}
        value={form[key]}
        onChange={e => setForm(p => ({ ...p, [key]: e.target.value }))}
        style={{
          width: '100%', padding: '10px 14px', border: '1px solid #ddd',
          borderRadius: 8, fontSize: 15, boxSizing: 'border-box'
        }}
      />
    </div>
  )

  return (
    <div style={{ padding: 40, maxWidth: 500 }}>
      <h2 style={{ marginBottom: 24 }}>Add New Bus</h2>
      {success && (
        <div style={{
          background: '#dcfce7', color: '#166534',
          padding: '12px 16px', borderRadius: 8, marginBottom: 20
        }}>
          ✅ Bus added successfully!
        </div>
      )}
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
          background: '#1E6BFF', color: 'white', border: 'none',
          padding: '14px 32px', borderRadius: 8, fontSize: 16,
          cursor: loading ? 'not-allowed' : 'pointer', width: '100%',
          opacity: loading ? 0.7 : 1
        }}>
        {loading ? 'Adding...' : 'Add Bus'}
      </button>
    </div>
  )
}