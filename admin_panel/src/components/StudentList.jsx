// src/components/StudentList.jsx
import { useState, useEffect } from 'react'
import { supabase } from '../supabaseClient'

export default function StudentList({ schoolId }) {
  const [students, setStudents] = useState([])
  const [buses, setBuses] = useState([])
  const [stops, setStops] = useState([])

  useEffect(() => {
    fetchStudents()
    fetchBuses()
  }, [])

  const fetchStudents = async () => {
    const { data } = await supabase
      .from('students')
      .select('*, buses(bus_number), stops(stop_name)')
      .eq('school_id', schoolId)
    setStudents(data || [])
  }

  const fetchBuses = async () => {
    const { data } = await supabase
      .from('buses')
      .select('id, bus_number')
      .eq('school_id', schoolId)
    setBuses(data || [])
  }

  const fetchStops = async (busId) => {
    const route = await supabase
      .from('routes')
      .select('id')
      .eq('bus_id', busId)
      .single()

    if (route.data) {
      const { data } = await supabase
        .from('stops')
        .select('id, stop_name, stop_order')
        .eq('route_id', route.data.id)
        .order('stop_order')
      setStops(data || [])
    }
  }

  const assignStudent = async (studentId, busId, stopId) => {
    await supabase
      .from('students')
      .update({ bus_id: busId, stop_id: stopId })
      .eq('id', studentId)

    // Also update user_roles table so parent sees the right bus
    const student = students.find(s => s.id === studentId)
    if (student) {
      await supabase
        .from('user_roles')
        .update({ bus_id: busId })
        .eq('school_id', schoolId)
    }
    fetchStudents()
    alert('Student assigned successfully!')
  }

  return (
    <div style={{ padding: 32 }}>
      <h2 style={{ marginBottom: 20 }}>Student Management</h2>

      <table style={{ width: '100%', borderCollapse: 'collapse' }}>
        <thead>
          <tr style={{ background: '#F1F5F9' }}>
            {['Student', 'Parent', 'Phone', 'Assigned Bus', 'Stop', 'Action']
              .map(h => (
                <th key={h} style={{
                  padding: '12px 16px', textAlign: 'left',
                  fontSize: 13, color: '#64748B'
                }}>{h}</th>
              ))}
          </tr>
        </thead>
        <tbody>
          {students.map(student => (
            <StudentRow
              key={student.id}
              student={student}
              buses={buses}
              stops={stops}
              onBusChange={fetchStops}
              onAssign={assignStudent}
            />
          ))}
        </tbody>
      </table>

      {students.length === 0 && (
        <div style={{ textAlign: 'center', padding: 40, color: '#94A3B8' }}>
          No students registered yet.
        </div>
      )}
    </div>
  )
}

function StudentRow({ student, buses, stops, onBusChange, onAssign }) {
  const [selectedBus, setSelectedBus] = useState(student.bus_id || '')
  const [selectedStop, setSelectedStop] = useState(student.stop_id || '')

  return (
    <tr style={{ borderBottom: '1px solid #E2E8F0' }}>
      <td style={{ padding: '14px 16px', fontWeight: 600 }}>
        {student.student_name}
      </td>
      <td style={{ padding: '14px 16px' }}>{student.parent_name}</td>
      <td style={{ padding: '14px 16px' }}>{student.parent_phone}</td>
      <td style={{ padding: '14px 16px' }}>
        <select
          value={selectedBus}
          onChange={e => {
            setSelectedBus(e.target.value)
            onBusChange(e.target.value)
          }}
          style={{ padding: '6px 10px', borderRadius: 6,
                   border: '1px solid #CBD5E1' }}>
          <option value=''>Select Bus</option>
          {buses.map(b => (
            <option key={b.id} value={b.id}>{b.bus_number}</option>
          ))}
        </select>
      </td>
      <td style={{ padding: '14px 16px' }}>
        <select
          value={selectedStop}
          onChange={e => setSelectedStop(e.target.value)}
          style={{ padding: '6px 10px', borderRadius: 6,
                   border: '1px solid #CBD5E1' }}
          disabled={!selectedBus}>
          <option value=''>Select Stop</option>
          {stops.map(s => (
            <option key={s.id} value={s.id}>{s.stop_name}</option>
          ))}
        </select>
      </td>
      <td style={{ padding: '14px 16px' }}>
        <button
          onClick={() => onAssign(student.id, selectedBus, selectedStop)}
          disabled={!selectedBus || !selectedStop}
          style={{
            background: '#1E6BFF', color: 'white',
            border: 'none', padding: '8px 16px',
            borderRadius: 6, cursor: 'pointer',
            opacity: (!selectedBus || !selectedStop) ? 0.5 : 1
          }}>
          Assign
        </button>
      </td>
    </tr>
  )
}