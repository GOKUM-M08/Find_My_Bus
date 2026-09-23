import { useState, useEffect } from 'react'
import { supabase } from '../supabaseClient'

const PRIMARY_BLUE = '#0052CC'

export default function StudentList({ schoolId }) {
  const [students, setStudents] = useState([])
  const [buses, setBuses] = useState([])
  const [loading, setLoading] = useState(true)
  const [notification, setNotification] = useState(null)

  useEffect(() => {
    loadData()
  }, [])

  const loadData = async () => {
    setLoading(true)
    try {
      const [{ data: studentData }, { data: busData }] = await Promise.all([
        supabase
          .from('students')
          .select('*, buses(bus_number), stops(stop_name)')
          .eq('school_id', schoolId),
        supabase
          .from('buses')
          .select('id, bus_number')
          .eq('school_id', schoolId)
      ])
      setStudents(studentData || [])
      setBuses(busData || [])
    } catch (e) {
      setNotification({ type: 'error', message: 'Failed to load student data.' })
    } finally {
      setLoading(false)
    }
  }

  const assignStudent = async (studentId, busId, stopId) => {
    try {
      await supabase
        .from('students')
        .update({ bus_id: busId, stop_id: stopId })
        .eq('id', studentId)

      const student = students.find(s => s.id === studentId)
      if (student) {
        await supabase
          .from('user_roles')
          .update({ bus_id: busId })
          .eq('school_id', schoolId)
      }
      setNotification({ type: 'success', message: 'Student bus and stop assigned successfully!' })
      loadData()
      setTimeout(() => setNotification(null), 3000)
    } catch (e) {
      setNotification({ type: 'error', message: 'Failed to assign student: ' + e.message })
    }
  }

  if (loading) {
    return (
      <div style={{ padding: 40, color: '#64748B', fontSize: 14 }}>
        Loading student records...
      </div>
    )
  }

  return (
    <div style={{ padding: '24px 16px', maxWidth: 1000, width: '100%', boxSizing: 'border-box' }}>
      <div style={{ marginBottom: 24 }}>
        <h2 style={{ margin: '0 0 6px', color: '#0F172A', fontSize: 20, fontWeight: 700 }}>
          🎓 Student Transport Assignments
        </h2>
        <p style={{ color: '#64748B', margin: 0, fontSize: 13 }}>
          Assign registered students to designated bus vehicles and pickup/drop-off stops.
        </p>
      </div>

      {notification && (
        <div style={{
          background: notification.type === 'error' ? '#FEE2E2' : '#DCFCE7',
          color: notification.type === 'error' ? '#991B1B' : '#166534',
          border: `1px solid ${notification.type === 'error' ? '#FECACA' : '#BBF7D0'}`,
          padding: '12px 16px', borderRadius: 10, marginBottom: 20, fontSize: 14, fontWeight: 600
        }}>
          {notification.type === 'error' ? '⚠️ ' : '✅ '}
          {notification.message}
        </div>
      )}

      {/* Responsive Table Wrapper with Horizontal Overflow Protection */}
      <div style={{ background: 'white', borderRadius: 12, border: '1px solid #E2E8F0', overflowX: 'auto', width: '100%', boxShadow: '0 4px 12px rgba(0,82,204,0.04)', boxSizing: 'border-box' }}>
        <table style={{ width: '100%', minWidth: 640, borderCollapse: 'collapse' }}>
          <thead>
            <tr style={{ background: '#F8FAFC', borderBottom: '1px solid #E2E8F0' }}>
              {['Student Name', 'Parent Name', 'Parent Contact', 'Assigned Bus', 'Assigned Stop', 'Action']
                .map(h => (
                  <th key={h} style={{
                    padding: '14px 16px', textAlign: 'left',
                    fontSize: 13, color: '#475569', fontWeight: 600, whiteSpace: 'nowrap'
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
                onAssign={assignStudent}
              />
            ))}
          </tbody>
        </table>

        {students.length === 0 && (
          <div style={{ textAlign: 'center', padding: '48px 24px', color: '#64748B' }}>
            <div style={{ fontSize: 32, marginBottom: 8 }}>🎓</div>
            <h4 style={{ margin: '0 0 4px', color: '#0F172A' }}>No registered students yet</h4>
            <p style={{ margin: 0, fontSize: 13 }}>Registered students will appear here for bus assignment.</p>
          </div>
        )}
      </div>
    </div>
  )
}

function StudentRow({ student, buses, onAssign }) {
  const [selectedBus, setSelectedBus] = useState(student.bus_id || '')
  const [selectedStop, setSelectedStop] = useState(student.stop_id || '')
  const [stops, setStops] = useState([])

  useEffect(() => {
    if (selectedBus) {
      fetchStops(selectedBus)
    } else {
      setStops([])
    }
  }, [selectedBus])

  const fetchStops = async (busId) => {
    const route = await supabase
      .from('routes')
      .select('id')
      .eq('bus_id', busId)
      .maybeSingle()

    if (route?.data) {
      const { data } = await supabase
        .from('stops')
        .select('id, stop_name, stop_order')
        .eq('route_id', route.data.id)
        .order('stop_order')
      setStops(data || [])
    } else {
      setStops([])
    }
  }

  return (
    <tr style={{ borderBottom: '1px solid #F1F5F9' }}>
      <td style={{ padding: '14px 16px', fontWeight: 600, color: '#0F172A', fontSize: 14 }}>
        {student.student_name}
      </td>
      <td style={{ padding: '14px 16px', fontSize: 14, color: '#334155' }}>{student.parent_name || '—'}</td>
      <td style={{ padding: '14px 16px', fontSize: 14, color: '#334155' }}>{student.parent_phone || '—'}</td>
      <td style={{ padding: '14px 16px' }}>
        <select
          value={selectedBus}
          onChange={e => setSelectedBus(e.target.value)}
          style={{ padding: '8px 12px', borderRadius: 6, border: '1px solid #CBD5E1', fontSize: 13 }}>
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
          style={{ padding: '8px 12px', borderRadius: 6, border: '1px solid #CBD5E1', fontSize: 13 }}
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
            background: (!selectedBus || !selectedStop) ? '#E2E8F0' : PRIMARY_BLUE,
            color: (!selectedBus || !selectedStop) ? '#94A3B8' : 'white',
            border: 'none', padding: '8px 16px', borderRadius: 6,
            cursor: (!selectedBus || !selectedStop) ? 'not-allowed' : 'pointer',
            fontWeight: 600, fontSize: 13, transition: 'all 0.2s'
          }}>
          Assign
        </button>
      </td>
    </tr>
  )
}