import { useState } from 'react'

const BACKEND_URL = window.location.hostname === 'localhost' ? 'http://localhost:8000' : ''
const PRIMARY_BLUE = '#0052CC'

export default function AddBus({ schoolId, onAdded }) {
  const [form, setForm] = useState({
    bus_number: '', bus_code: '', driver_name: '',
    driver_phone: '', device_id: '', capacity: 40
  })
  const [loading, setLoading] = useState(false)
  const [success, setSuccess] = useState(false)
  const [error, setError] = useState(null)

  const handleSubmit = async () => {
    setError(null)
    if (!form.bus_number.trim() || !form.device_id.trim()) {
      setError('Bus registration number and GPS Device ID are required.')
      return
    }
    setLoading(true)
    try {
      const response = await fetch(`${BACKEND_URL}/api/buses/`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          ...form,
          capacity: Number(form.capacity) || 40,
          school_id: schoolId
        })
      })
      if (!response.ok) {
        const err = await response.json().catch(() => ({}))
        throw new Error(err.detail ? (typeof err.detail === 'string' ? err.detail : JSON.stringify(err.detail)) : `Request failed (${response.status})`)
      }
      setSuccess(true)
      setForm({ bus_number: '', bus_code: '', driver_name: '',
                 driver_phone: '', device_id: '', capacity: 40 })
      if (onAdded) onAdded()
      setTimeout(() => setSuccess(false), 3000)
    } catch (err) {
      setError(err.message)
    } finally {
      setLoading(false)
    }
  }

  const field = (label, key, placeholder, type = 'text') => (
    <div style={{ marginBottom: 18 }}>
      <label style={{ display: 'block', marginBottom: 6, fontWeight: 600, fontSize: 14, color: '#0F172A' }}>
        {label}
      </label>
      <input
        type={type}
        value={form[key]}
        placeholder={placeholder}
        onChange={e => setForm(p => ({ ...p, [key]: e.target.value }))}
        style={{
          width: '100%', padding: '12px 14px', border: '1px solid #E2E8F0',
          borderRadius: 8, fontSize: 14, boxSizing: 'border-box',
          outline: 'none', transition: 'border-color 0.2s'
        }}
        onFocus={(e) => e.target.style.borderColor = PRIMARY_BLUE}
        onBlur={(e) => e.target.style.borderColor = '#E2E8F0'}
      />
    </div>
  )

  return (
    <div style={{ padding: '24px 16px', maxWidth: 640, width: '100%', background: '#F7F9FC', minHeight: '100vh', boxSizing: 'border-box' }}>
      <div style={{ marginBottom: 24 }}>
        <h2 style={{ margin: '0 0 6px', color: '#0F172A', fontSize: 20, fontWeight: 700 }}>
          🚌 Vehicle Fleet Registration
        </h2>
        <p style={{ color: '#64748B', margin: 0, fontSize: 13 }}>
          Register a new vehicle into your school transport fleet.
        </p>
      </div>

      {success && (
        <div style={{
          background: '#DCFCE7', color: '#166534',
          padding: '14px 16px', borderRadius: 10, marginBottom: 20,
          border: '1px solid #BBF7D0', fontSize: 14, fontWeight: 600
        }}>
          ✅ Bus registered successfully!
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
        {field('Bus Registration Number *', 'bus_number', 'e.g. TN09 AB 1234')}
        {field('Bus Code / Designation', 'bus_code', 'e.g. Bus-A')}
        {field('Assigned Driver Name', 'driver_name', 'e.g. John Doe')}
        {field('Driver Phone Number', 'driver_phone', 'e.g. +91 9876543210')}
        {field('GPS Tracker Device Serial ID *', 'device_id', 'e.g. DEVICE123')}
        {field('Seating Capacity (Students)', 'capacity', '40', 'number')}

        <button
          onClick={handleSubmit}
          disabled={loading}
          style={{
            background: loading ? '#94A3B8' : PRIMARY_BLUE,
            color: 'white', border: 'none',
            padding: '14px 24px', borderRadius: 8, fontSize: 15,
            cursor: loading ? 'not-allowed' : 'pointer', width: '100%',
            fontWeight: 600, transition: 'background 0.2s', marginTop: 12
          }}
          onMouseEnter={(e) => !loading && (e.target.style.background = '#00338C')}
          onMouseLeave={(e) => !loading && (e.target.style.background = PRIMARY_BLUE)}
        >
          {loading ? 'Registering Bus...' : '➕ Register Vehicle'}
        </button>
      </div>
    </div>
  )
}