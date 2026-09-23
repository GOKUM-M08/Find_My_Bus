import { GoogleMap, Marker, useLoadScript } from '@react-google-maps/api'

const mapContainerStyle = { width: '100%', height: 'calc(100% - 68px)' }
const center = { lat: 13.0827, lng: 80.2707 } // Chennai default
const PRIMARY_BLUE = '#0052CC'

// Custom SVG icon for bus
const BUS_ICON_SVG = `
<svg width="36" height="36" viewBox="0 0 100 100" xmlns="http://www.w3.org/2000/svg">
  <g>
    <path d="M 15 45 L 85 40 L 85 85 L 15 85 Z" fill="#001A4D" opacity="0.3"/>
    <rect x="15" y="25" width="70" height="40" rx="5" fill="#0052CC"/>
    <rect x="15" y="25" width="15" height="40" fill="#00338C" rx="5"/>
    <rect x="22" y="32" width="12" height="10" fill="#87CEEB" rx="1"/>
    <rect x="38" y="32" width="12" height="10" fill="#87CEEB" rx="1"/>
    <rect x="54" y="32" width="12" height="10" fill="#87CEEB" rx="1"/>
    <rect x="70" y="32" width="8" height="18" fill="#00338C" rx="1"/>
    <circle cx="76" cy="42" r="1.5" fill="#FFD700"/>
    <circle cx="28" cy="68" r="5" fill="#333"/>
    <circle cx="28" cy="68" r="3" fill="#666"/>
    <circle cx="72" cy="68" r="5" fill="#333"/>
    <circle cx="72" cy="68" r="3" fill="#666"/>
  </g>
</svg>
`.trim()

const createBusIcon = () => {
  return {
    url: `data:image/svg+xml;base64,${btoa(BUS_ICON_SVG)}`,
    scaledSize: new window.google.maps.Size(36, 36),
    anchor: new window.google.maps.Point(18, 18),
  }
}

export default function BusMap({ buses }) {
  const { isLoaded } = useLoadScript({
    googleMapsApiKey: 'AIzaSyDaTPBXsHG95vazfTUSTW0GRZPDf_lUghE'
  })

  const onlineCount = buses.filter(b => b.location).length
  const offlineCount = buses.length - onlineCount

  if (!isLoaded) return <div style={{ padding: 40, color: '#64748B' }}>Loading live fleet map...</div>

  return (
    <div style={{ height: '100%', display: 'flex', flexDirection: 'column', position: 'relative' }}>
      {/* Status Summary Strip (Responsive & Overflow Protected) */}
      <div style={{
        minHeight: 56, background: 'white', borderBottom: '1px solid #E2E8F0',
        padding: '8px 16px', display: 'flex', alignItems: 'center', justifyContent: 'space-between',
        flexWrap: 'wrap', gap: 12, boxShadow: '0 2px 8px rgba(0,0,0,0.04)', zIndex: 10,
        boxSizing: 'border-box'
      }}>
        <div style={{ display: 'flex', alignItems: 'center', gap: 12, flexWrap: 'wrap' }}>
          <h3 style={{ margin: 0, fontSize: 15, color: '#0F172A', fontWeight: 700 }}>
            🗺️ Live Fleet Overview
          </h3>
          <div style={{ display: 'flex', gap: 8, flexWrap: 'wrap' }}>
            <span style={{
              background: '#DCFCE7', color: '#166534', padding: '4px 10px',
              borderRadius: 20, fontSize: 12, fontWeight: 600, display: 'flex', alignItems: 'center', gap: 6
            }}>
              <span style={{ width: 8, height: 8, borderRadius: '50%', background: '#10B981' }} />
              {onlineCount} Online
            </span>
            <span style={{
              background: '#F1F5F9', color: '#475569', padding: '4px 10px',
              borderRadius: 20, fontSize: 12, fontWeight: 600, display: 'flex', alignItems: 'center', gap: 6
            }}>
              <span style={{ width: 8, height: 8, borderRadius: '50%', background: '#94A3B8' }} />
              {offlineCount} Offline
            </span>
          </div>
        </div>

        <div style={{ display: 'flex', alignItems: 'center', gap: 12 }}>
          <span style={{ fontSize: 12, color: '#64748B' }}>
            Total Fleet: <strong>{buses.length}</strong> vehicles
          </span>
        </div>
      </div>

      {/* Map view */}
      <div style={{ flex: 1, position: 'relative' }}>
        <GoogleMap mapContainerStyle={{ width: '100%', height: '100%' }} zoom={12} center={center}>
          {buses.map(bus => bus.location && (
            <Marker
              key={bus.id}
              position={{
                lat: bus.location.latitude,
                lng: bus.location.longitude
              }}
              icon={createBusIcon()}
              title={`${bus.bus_number} - ${bus.driver_name || 'Driver'}`}
              label={{
                text: bus.bus_code || '🚌',
                color: 'white',
                fontSize: '10px',
                fontWeight: 'bold'
              }}
            />
          ))}
        </GoogleMap>

        {/* Responsive Bus list overlay */}
        <div style={{
          position: 'absolute', top: 12, right: 12,
          background: 'white', borderRadius: 12,
          padding: 14, width: 240, maxWidth: 'calc(100vw - 40px)',
          boxShadow: '0 8px 24px rgba(0, 82, 204, 0.12)',
          maxHeight: 'calc(100% - 24px)', overflowY: 'auto',
          border: `1px solid #E2E8F0`, boxSizing: 'border-box'
        }}>
          <h4 style={{ margin: '0 0 12px', fontSize: 14, color: '#0F172A', fontWeight: 700 }}>
            🚌 Vehicles ({onlineCount}/{buses.length})
          </h4>
          {buses.length === 0 ? (
            <div style={{ fontSize: 13, color: '#64748B', textAlign: 'center', padding: '16px 0' }}>
              No buses registered yet.
            </div>
          ) : (
            buses.map(bus => (
              <div key={bus.id} style={{
                padding: '10px 0', borderBottom: '1px solid #F1F5F9',
                display: 'flex', justifyContent: 'space-between', alignItems: 'center'
              }}>
                <div>
                  <span style={{ fontWeight: 600, color: '#0F172A', fontSize: 14, display: 'block' }}>
                    {bus.bus_number}
                  </span>
                  <span style={{ fontSize: 12, color: '#64748B' }}>
                    {bus.driver_name || 'No driver assigned'}
                  </span>
                </div>
                <span style={{
                  color: bus.location ? '#10B981' : '#94A3B8',
                  fontSize: 12, fontWeight: 600,
                  background: bus.location ? '#DCFCE7' : '#F1F5F9',
                  padding: '4px 8px', borderRadius: 6
                }}>
                  {bus.location
                    ? `${bus.location.speed?.toFixed(0) || 0} km/h`
                    : 'Offline'}
                </span>
              </div>
            ))
          )}
        </div>
      </div>
    </div>
  )
}