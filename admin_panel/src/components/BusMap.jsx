import { GoogleMap, Marker, Polyline, useLoadScript } from '@react-google-maps/api'

const mapContainerStyle = { width: '100%', height: '100%' }
const center = { lat: 13.0827, lng: 80.2707 } // Chennai default
const PRIMARY_BLUE = '#0052CC'

// Custom SVG icon for bus (3D classic look, small size)
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

  if (!isLoaded) return <div style={{ padding: 40 }}>Loading map...</div>

  return (
    <div style={{ height: '100%', position: 'relative' }}>
      <GoogleMap mapContainerStyle={mapContainerStyle} zoom={12} center={center}>
        {buses.map(bus => bus.location && (
          <Marker
            key={bus.id}
            position={{
              lat: bus.location.latitude,
              lng: bus.location.longitude
            }}
            icon={createBusIcon()}
            title={`${bus.bus_number} - ${bus.driver_name}`}
            label={{
              text: bus.bus_code || '🚌',
              color: 'white',
              fontSize: '10px',
              fontWeight: 'bold'
            }}
          />
        ))}
      </GoogleMap>

      {/* Bus list overlay */}
      <div style={{
        position: 'absolute', top: 16, right: 16,
        background: 'white', borderRadius: 12,
        padding: 16, width: 240, boxShadow: '0 8px 24px rgba(0, 82, 204, 0.15)',
        maxHeight: 'calc(100% - 32px)', overflowY: 'auto',
        border: `2px solid ${PRIMARY_BLUE}`
      }}>
        <h3 style={{ margin: '0 0 12px', fontSize: 14, color: PRIMARY_BLUE, fontWeight: 700 }}>
          🚌 LIVE BUSES ({buses.filter(b => b.location).length}/{buses.length})
        </h3>
        {buses.map(bus => (
          <div key={bus.id} style={{
            padding: '10px 0', borderBottom: '1px solid #eee',
            display: 'flex', justifyContent: 'space-between', alignItems: 'center'
          }}>
            <div>
              <span style={{ fontWeight: 600, color: '#333', display: 'block' }}>{bus.bus_number}</span>
              <span style={{ fontSize: 11, color: '#999' }}>{bus.driver_name || 'N/A'}</span>
            </div>
            <span style={{
              color: bus.location ? PRIMARY_BLUE : '#ccc',
              fontSize: 12, fontWeight: 600,
              background: bus.location ? '#E8F0FE' : '#f5f5f5',
              padding: '4px 8px', borderRadius: 6
            }}>
              {bus.location
                ? `${bus.location.speed?.toFixed(0) || 0} km/h`
                : 'Offline'}
            </span>
          </div>
        ))}
      </div>
    </div>
  )
}