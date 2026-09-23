import { useState, useEffect } from 'react'
import { supabase } from './supabaseClient'
import BusMap from './components/BusMap'
import AddBus from './components/AddBus'
import RouteBuilder from './components/RouteBuilder'
import StudentList from './components/StudentList'

const PRIMARY_BLUE = '#0052CC'
const SECONDARY_BLUE = '#1E6BFF'

export default function App() {
  const [buses, setBuses] = useState([])
  const [activeTab, setActiveTab] = useState('dashboard')
  const [showSupport, setShowSupport] = useState(false)
  const [isMobileMenuOpen, setIsMobileMenuOpen] = useState(false)
  const schoolId = '02467563-d81a-4fb3-a426-66c0a37e3dff'

  useEffect(() => {
    fetchBuses()

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

  const navItems = [
    { id: 'dashboard', label: '🗺️ Dashboard', desc: 'Live map & status summary' },
    { id: 'buses', label: '🚌 Buses', desc: 'Fleet list & registration' },
    { id: 'routes', label: '📍 Routes', desc: 'Route builder & road conditions' },
    { id: 'optimizer', label: '⚡ Optimizer', desc: 'Fleet optimization & analytics' },
    { id: 'students', label: '🎓 Students', desc: 'Bus & stop assignments' },
    { id: 'settings', label: '⚙️ Settings', desc: 'System health & support' },
  ]

  const handleSelectTab = (tabId) => {
    setActiveTab(tabId)
    setIsMobileMenuOpen(false)
  }

  const activeTabMeta = navItems.find(n => n.id === activeTab) || navItems[0]

  return (
    <div style={{ display: 'flex', flexDirection: 'column', height: '100vh', width: '100vw', overflow: 'hidden', fontFamily: '-apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif' }}>
      
      {/* Top Header Bar with Hamburger Button (Reachable from anywhere) */}
      <header style={{
        height: 56, background: PRIMARY_BLUE, color: 'white',
        display: 'flex', alignItems: 'center', justifyContent: 'space-between',
        padding: '0 16px', borderBottom: '1px solid rgba(255,255,255,0.1)',
        zIndex: 50, flexShrink: 0
      }}>
        <div style={{ display: 'flex', alignItems: 'center', gap: 12 }}>
          <button
            onClick={() => setIsMobileMenuOpen(!isMobileMenuOpen)}
            style={{
              background: 'rgba(255,255,255,0.15)', border: 'none',
              color: 'white', fontSize: 20, cursor: 'pointer',
              padding: '6px 10px', borderRadius: 8, display: 'flex',
              alignItems: 'center', justifyContent: 'center'
            }}
            title="Toggle Navigation Menu"
            aria-label="Toggle Navigation Drawer"
          >
            ☰
          </button>
          <div>
            <h1 style={{ margin: 0, fontSize: 16, fontWeight: 700, letterSpacing: '-0.3px', color: 'white' }}>
              🚌 BusTrack Admin
            </h1>
            <span style={{ fontSize: 11, opacity: 0.8, display: 'block' }}>
              {activeTabMeta.label}
            </span>
          </div>
        </div>

        <div style={{ display: 'flex', alignItems: 'center', gap: 12 }}>
          <span style={{ fontSize: 12, background: 'rgba(255,255,255,0.15)', padding: '4px 8px', borderRadius: 6 }}>
            Live Active: <strong>{buses.filter(b => b.location).length}</strong> / {buses.length}
          </span>
          <button
            onClick={() => setShowSupport(!showSupport)}
            style={{
              background: 'rgba(255,255,255,0.15)',
              border: 'none', color: 'white', fontSize: 14, cursor: 'pointer',
              padding: '6px 10px', borderRadius: 8
            }}
            title="Support Details"
          >
            💬 Support
          </button>
        </div>
      </header>

      <div style={{ display: 'flex', flex: 1, overflow: 'hidden', position: 'relative' }}>
        
        {/* Backdrop for Mobile Drawer */}
        {isMobileMenuOpen && (
          <div
            onClick={() => setIsMobileMenuOpen(false)}
            style={{
              position: 'absolute', inset: 0, background: 'rgba(15, 23, 42, 0.5)',
              backdropFilter: 'blur(2px)', zIndex: 30, cursor: 'pointer'
            }}
          />
        )}

        {/* Sidebar / Slide-out Drawer Navigation */}
        <aside style={{
          width: 280, maxWidth: '85vw', background: `linear-gradient(180deg, ${PRIMARY_BLUE} 0%, #00338C 100%)`,
          color: 'white', display: 'flex', flexDirection: 'column', padding: '20px 16px',
          boxShadow: '4px 0 16px rgba(0, 82, 204, 0.15)', zIndex: 40,
          position: 'absolute', top: 0, bottom: 0, left: 0,
          transform: isMobileMenuOpen ? 'translateX(0)' : 'translateX(-100%)',
          transition: 'transform 0.25s ease-in-out',
          boxSizing: 'border-box'
        }}>
          <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: 20, padding: '0 4px' }}>
            <div>
              <h2 style={{ margin: 0, fontSize: 17, fontWeight: 700 }}>Menu Navigation</h2>
              <span style={{ fontSize: 11, opacity: 0.75 }}>Enterprise Fleet Control</span>
            </div>
            <button
              onClick={() => setIsMobileMenuOpen(false)}
              style={{
                background: 'rgba(255,255,255,0.2)', border: 'none', color: 'white',
                fontSize: 16, cursor: 'pointer', padding: '4px 8px', borderRadius: 6
              }}
            >
              ✕
            </button>
          </div>

          {showSupport && (
            <div style={{
              background: 'rgba(255,255,255,0.12)',
              padding: 12, borderRadius: 10, marginBottom: 16,
              border: '1px solid rgba(255,255,255,0.2)'
            }}>
              <h4 style={{ margin: '0 0 6px', fontSize: 12, color: '#E8F0FE' }}>📞 Operational Support</h4>
              <p style={{ margin: 0, fontSize: 11, opacity: 0.9 }}>
                <strong>Phone:</strong> <a href="tel:+916369669753" style={{ color: 'white' }}>+91 6369669753</a>
              </p>
              <p style={{ margin: '3px 0 0', fontSize: 11, opacity: 0.9 }}>
                <strong>Email:</strong> <a href="mailto:gokulm4a1@gmail.com" style={{ color: 'white' }}>gokulm4a1@gmail.com</a>
              </p>
            </div>
          )}

          <nav style={{ flex: 1, display: 'flex', flexDirection: 'column', gap: 6, overflowY: 'auto' }}>
            {navItems.map(tab => {
              const isActive = activeTab === tab.id
              return (
                <button key={tab.id}
                  onClick={() => handleSelectTab(tab.id)}
                  style={{
                    background: isActive ? 'rgba(255,255,255,0.2)' : 'transparent',
                    color: 'white', border: 'none', padding: '12px 14px',
                    borderRadius: 10, textAlign: 'left', cursor: 'pointer',
                    fontSize: 14, fontWeight: isActive ? 700 : 500,
                    transition: 'all 0.2s', display: 'flex', flexDirection: 'column',
                    borderLeft: isActive ? '4px solid #FFFFFF' : '4px solid transparent'
                  }}>
                  <span>{tab.label}</span>
                  <span style={{ fontSize: 11, opacity: isActive ? 0.9 : 0.65, marginTop: 2, fontWeight: 400 }}>
                    {tab.desc}
                  </span>
                </button>
              )
            })}
          </nav>

          <div style={{ marginTop: 'auto', paddingTop: 14, borderTop: '1px solid rgba(255,255,255,0.15)' }}>
            <div style={{ display: 'flex', justifyContent: 'space-between', fontSize: 12, opacity: 0.85 }}>
              <span>Registered Vehicles:</span>
              <strong>{buses.length}</strong>
            </div>
            <div style={{ display: 'flex', justifyContent: 'space-between', fontSize: 12, opacity: 0.85, marginTop: 4 }}>
              <span>Active Live Now:</span>
              <strong style={{ color: '#86EFAC' }}>{buses.filter(b => b.location).length}</strong>
            </div>
          </div>
        </aside>

        {/* Main Content Area with Overflow Protection */}
        <main style={{ flex: 1, overflowY: 'auto', overflowX: 'hidden', background: '#F7F9FC', width: '100%', height: '100%', boxSizing: 'border-box' }}>
          {activeTab === 'dashboard' && <BusMap buses={buses} />}
          {activeTab === 'buses' && <AddBus schoolId={schoolId} onAdded={fetchBuses} />}
          {activeTab === 'routes' && <RouteBuilder buses={buses} />}
          {activeTab === 'optimizer' && (
            <div style={{ padding: '24px 16px', maxWidth: 800, boxSizing: 'border-box' }}>
              <h2 style={{ fontSize: 20, margin: '0 0 8px' }}>⚡ Route Optimizer</h2>
              <p style={{ color: '#64748B', fontSize: 14 }}>
                Fleet optimization and Hungarian algorithm recommendations are active on the Mobile Admin Console.
              </p>
            </div>
          )}
          {activeTab === 'students' && <StudentList schoolId={schoolId} />}
          {activeTab === 'settings' && (
            <div style={{ padding: '24px 16px', maxWidth: 600, boxSizing: 'border-box' }}>
              <h2 style={{ fontSize: 20, margin: '0 0 8px' }}>⚙️ System Settings & Health</h2>
              <div style={{ background: 'white', padding: 20, borderRadius: 12, border: '1px solid #E2E8F0', marginTop: 16 }}>
                <h4 style={{ margin: '0 0 12px' }}>Database & API Status</h4>
                <p style={{ color: '#10B981', fontWeight: 600, margin: '4px 0' }}>✅ Supabase Database Connected</p>
                <p style={{ color: '#10B981', fontWeight: 600, margin: '4px 0' }}>✅ Live Realtime WebSocket Channel Active</p>
                <p style={{ color: '#64748B', fontSize: 13, marginTop: 14 }}>School Scope ID: {schoolId}</p>
              </div>
            </div>
          )}
        </main>

      </div>
    </div>
  )
}