import { useState, useEffect } from 'react'
import { supabase } from './supabaseClient'
import BusMap from './components/BusMap'
import AddBus from './components/AddBus'
import RouteBuilder from './components/RouteBuilder'

const PRIMARY_BLUE = '#0052CC'
const SECONDARY_BLUE = '#1E6BFF'
const LIGHT_BLUE = '#E8F0FE'

export default function App() {
  const [buses, setBuses] = useState([])
  const [activeTab, setActiveTab] = useState('map')
  const [showSupport, setShowSupport] = useState(false)
  const schoolId = '02467563-d81a-4fb3-a426-66c0a37e3dff'

  useEffect(() => {
    fetchBuses()
    
    // Real-time subscription to live_location table
    const subscription = supabase
      .channel('live-locations')
      .on('postgres_changes', {
        event: '*',
        schema: 'public',
        table: 'live_location'
      }, payload => {
        updateBusLocation(payload.new)
      })
      .subscribe()

    return () => supabase.removeChannel(subscription)
  }, [])

  const fetchBuses = async () => {
    const { data: busData } = await supabase
      .from('buses')
      .select('*')
      .eq('school_id', schoolId)

    if (!busData) {
      setBuses([])
      return
    }

    // Also pull any existing live_location rows so buses that were
    // already being tracked before this page loaded show as active
    // right away, instead of waiting for the next GPS update.
    const { data: locationData } = await supabase
      .from('live_location')
      .select('*')

    const merged = busData.map(bus => ({
      ...bus,
      location: locationData?.find(loc => loc.bus_id === bus.id) || null,
    }))

    setBuses(merged)
  }

  const updateBusLocation = (locationData) => {
    setBuses(prev => prev.map(bus =>
      bus.id === locationData.bus_id
        ? { ...bus, location: locationData }
        : bus
    ))
  }

  return (
    <div style={{ display: 'flex', height: '100vh', fontFamily: 'sans-serif' }}>
      {/* Sidebar */}
      <div style={{
        width: 280, background: `linear-gradient(135deg, ${PRIMARY_BLUE}, ${SECONDARY_BLUE})`, 
        color: 'white', display: 'flex', flexDirection: 'column', padding: 24,
        boxShadow: '0 8px 24px rgba(0, 82, 204, 0.15)'
      }}>
        <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: 32 }}>
          <h2 style={{ margin: 0 }}>🚌 BusTrack Admin</h2>
          <button
            onClick={() => setShowSupport(!showSupport)}
            style={{
              background: 'rgba(255,255,255,0.2)',
              border: 'none', color: 'white', fontSize: 20, cursor: 'pointer',
              padding: '8px 12px', borderRadius: 6, transition: 'all 0.3s'
            }}
            title="Support Menu"
          >
            ☰
          </button>
        </div>

        {showSupport && (
          <div style={{
            background: 'rgba(255,255,255,0.1)',
            padding: 16, borderRadius: 12, marginBottom: 24,
            backdropFilter: 'blur(10px)', border: '1px solid rgba(255,255,255,0.2)'
          }}>
            <h4 style={{ margin: '0 0 12px', fontSize: 13 }}>📞 Support</h4>
            <p style={{ margin: 0, fontSize: 12, opacity: 0.9 }}>
              <strong>Phone:</strong><br/>
              <a href="tel:+916369669753" style={{ color: 'white', textDecoration: 'none' }}>+91 6369669753</a>
            </p>
            <p style={{ margin: '8px 0 0', fontSize: 12, opacity: 0.9 }}>
              <strong>Email:</strong><br/>
              <a href="mailto:gokulm4a1@gmail.com" style={{ color: 'white', textDecoration: 'none' }}>gokulm4a1@gmail.com</a>
            </p>
          </div>
        )}

        {[
          { id: 'map', label: '🗺️ Live Map' },
          { id: 'add', label: '➕ Add Bus' },
          { id: 'route', label: '📍 Build Route' },
        ].map(tab => (
          <button key={tab.id}
            onClick={() => setActiveTab(tab.id)}
            style={{
              background: activeTab === tab.id ? 'rgba(255,255,255,0.25)' : 'transparent',
              color: 'white', border: 'none', padding: '14px 16px',
              borderRadius: 10, textAlign: 'left', cursor: 'pointer',
              marginBottom: 10, fontSize: 15, fontWeight: activeTab === tab.id ? 600 : 500,
              transition: 'all 0.3s', borderLeft: activeTab === tab.id ? `4px solid white` : '4px solid transparent'
            }}>
            {tab.label}
          </button>
        ))}

        <div style={{ marginTop: 'auto', paddingTop: 20, borderTop: '1px solid rgba(255,255,255,0.2)' }}>
          <p style={{ fontSize: 12, opacity: 0.8, margin: 0 }}>
            <strong>{buses.length}</strong> buses registered
          </p>
          <p style={{ fontSize: 11, opacity: 0.6, margin: '8px 0 0' }}>
            {buses.filter(b => b.location).length} active now
          </p>
        </div>
      </div>

      {/* Main Content */}
      <div style={{ flex: 1, overflow: 'auto', background: '#F7F9FC' }}>
        {activeTab === 'map' && <BusMap buses={buses} />}
        {activeTab === 'add' && <AddBus schoolId={schoolId} onAdded={fetchBuses} />}
        {activeTab === 'route' && <RouteBuilder buses={buses} />}
      </div>
    </div>
  )
}