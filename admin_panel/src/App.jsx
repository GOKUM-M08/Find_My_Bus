import { useState, useEffect } from 'react'
import { supabase } from './supabaseClient'
import BusMap from './components/BusMap'
import AddBus from './components/AddBus'
import RouteBuilder from './components/RouteBuilder'

export default function App() {
  const [buses, setBuses] = useState([])
  const [activeTab, setActiveTab] = useState('map')
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
        width: 240, background: '#1E6BFF', color: 'white',
        display: 'flex', flexDirection: 'column', padding: 20
      }}>
        <h2 style={{ margin: '0 0 32px' }}>🚌 BusTrack Admin</h2>
        {[
          { id: 'map', label: '🗺️ Live Map' },
          { id: 'add', label: '➕ Add Bus' },
          { id: 'route', label: '📍 Build Route' },
        ].map(tab => (
          <button key={tab.id}
            onClick={() => setActiveTab(tab.id)}
            style={{
              background: activeTab === tab.id ? 'rgba(255,255,255,0.2)' : 'transparent',
              color: 'white', border: 'none', padding: '12px 16px',
              borderRadius: 8, textAlign: 'left', cursor: 'pointer',
              marginBottom: 8, fontSize: 15
            }}>
            {tab.label}
          </button>
        ))}

        <div style={{ marginTop: 'auto' }}>
          <p style={{ fontSize: 12, opacity: 0.7 }}>
            {buses.length} buses registered
          </p>
        </div>
      </div>

      {/* Main Content */}
      <div style={{ flex: 1, overflow: 'auto' }}>
        {activeTab === 'map' && <BusMap buses={buses} />}
        {activeTab === 'add' && <AddBus schoolId={schoolId} onAdded={fetchBuses} />}
        {activeTab === 'route' && <RouteBuilder buses={buses} />}
      </div>
    </div>
  )
}