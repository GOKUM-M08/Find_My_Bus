import { GoogleMap, Marker, Polyline, useLoadScript } from '@react-google-maps/api'

const mapContainerStyle = { width: '100%', height: '100%' }
const center = { lat: 13.0827, lng: 80.2707 } // Chennai default

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
            title={`${bus.bus_number} - ${bus.driver_name}`}
            label={bus.bus_code}
          />
        ))}
      </GoogleMap>

      {/* Bus list overlay */}
      <div style={{
        position: 'absolute', top: 16, right: 16,
        background: 'white', borderRadius: 12,
        padding: 16, width: 240, boxShadow: '0 4px 20px rgba(0,0,0,0.1)'
      }}>
        <h3 style={{ margin: '0 0 12px', fontSize: 14, color: '#666' }}>
          LIVE BUSES ({buses.filter(b => b.location).length} active)
        </h3>
        {buses.map(bus => (
          <div key={bus.id} style={{
            padding: '8px 0', borderBottom: '1px solid #eee',
            display: 'flex', justifyContent: 'space-between'
          }}>
            <span style={{ fontWeight: 600 }}>{bus.bus_number}</span>
            <span style={{
              color: bus.location ? '#22c55e' : '#999',
              fontSize: 12
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