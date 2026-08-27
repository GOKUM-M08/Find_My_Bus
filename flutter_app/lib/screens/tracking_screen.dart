import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:http/http.dart' as http;

// TODO: replace with your deployed backend URL (see STEP 6 — Deployment)
const String kBackendBaseUrl = 'http://192.168.1.5:8000';

class TrackingScreen extends StatefulWidget {
  final String busId;
  final String busNumber;
  // Optional: the parent's stop id, used to calculate ETA (STEP 11).
  final String? stopId;

  const TrackingScreen({
    super.key,
    required this.busId,
    required this.busNumber,
    this.stopId,
  });

  @override
  State<TrackingScreen> createState() => _TrackingScreenState();
}

class _TrackingScreenState extends State<TrackingScreen> {
  GoogleMapController? _mapController;
  Marker? _busMarker;
  Set<Polyline> _routeLines = {};
  Set<Marker> _stopMarkers = {};

  WebSocketChannel? _wsChannel;
  LatLng _currentBusLocation = const LatLng(13.0827, 80.2707);
  double _busSpeed = 0;
  String _eta = "Calculating...";
  int _stopsAway = 0;
  Timer? _etaTimer;

  final supabase = Supabase.instance.client;

  @override
  void initState() {
    super.initState();
    _loadRoute();
    _connectWebSocket();
    _loadInitialLocation();

    // STEP 11.3 — fetch ETA once immediately, then refresh every 30 seconds.
    if (widget.stopId != null) {
      _fetchETA(widget.stopId!);
      _etaTimer = Timer.periodic(const Duration(seconds: 30), (_) {
        _fetchETA(widget.stopId!);
      });
    }
  }

  Future<void> _loadInitialLocation() async {
    // Get latest location from API
    final response = await supabase
        .from('live_location')
        .select()
        .eq('bus_id', widget.busId)
        .single();

    if (response != null) {
      setState(() {
        _currentBusLocation = LatLng(
          response['latitude'],
          response['longitude'],
        );
        _busSpeed = response['speed']?.toDouble() ?? 0;
        _updateBusMarker();
      });
    }
  }

  Future<void> _loadRoute() async {
    // Load route stops from Supabase
    final routes = await supabase
        .from('routes')
        .select('*, stops(*)')
        .eq('bus_id', widget.busId)
        .single();

    if (routes != null && routes['stops'] != null) {
      List<LatLng> routePoints = [];
      Set<Marker> stopMarkers = {};

      final stops = routes['stops'] as List;
      stops.sort((a, b) => a['stop_order'].compareTo(b['stop_order']));

      for (var stop in stops) {
        LatLng pos = LatLng(stop['latitude'], stop['longitude']);
        routePoints.add(pos);

        stopMarkers.add(Marker(
          markerId: MarkerId(stop['id']),
          position: pos,
          icon: BitmapDescriptor.defaultMarkerWithHue(
              BitmapDescriptor.hueAzure),
          infoWindow: InfoWindow(
            title: stop['stop_name'],
            snippet: stop['expected_time'] ?? '',
          ),
        ));
      }

      setState(() {
        _routeLines = {
          Polyline(
            polylineId: const PolylineId('route'),
            points: routePoints,
            color: const Color(0xFF1E6BFF),
            width: 4,
          ),
        };
        _stopMarkers = stopMarkers;
      });
    }
  }

  void _connectWebSocket() {
    // Connect to your FastAPI WebSocket for real-time updates
    _wsChannel = WebSocketChannel.connect(
  Uri.parse('ws://192.168.1.5:8000/ws/track/${widget.busId}'),
);

    _wsChannel!.stream.listen((data) {
      final parsed = json.decode(data);
      if (parsed['type'] == 'ping') return;

      setState(() {
        _currentBusLocation = LatLng(
          parsed['latitude'],
          parsed['longitude'],
        );
        _busSpeed = parsed['speed']?.toDouble() ?? 0;
        _updateBusMarker();
        // Move camera to follow bus
        _mapController?.animateCamera(
          CameraUpdate.newLatLng(_currentBusLocation),
        );
      });

      // A fresh GPS point just came in — refresh ETA too.
      if (widget.stopId != null) {
        _fetchETA(widget.stopId!);
      }
    });
  }

  void _updateBusMarker() {
    _busMarker = Marker(
      markerId: const MarkerId('bus'),
      position: _currentBusLocation,
      icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
      infoWindow: InfoWindow(
        title: 'Bus ${widget.busNumber}',
        snippet: '${_busSpeed.toStringAsFixed(0)} km/h',
      ),
    );
  }

  // STEP 11.3 — Show ETA in Flutter Tracking Screen
  Future<void> _fetchETA(String stopId) async {
    try {
      final response = await http.get(Uri.parse(
        '$kBackendBaseUrl/api/tracking'
        '/${widget.busId}/eta/$stopId',
      ));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        setState(() {
          _eta = data['eta'] ?? 'Calculating...';
          _stopsAway = data['stops_away'] ?? 0;
        });
      }
    } catch (e) {
      setState(() => _eta = 'Unavailable');
    }
  }

  @override
  void dispose() {
    _wsChannel?.sink.close();
    _mapController?.dispose();
    _etaTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Bus ${widget.busNumber}'),
        backgroundColor: const Color(0xFF1E6BFF),
        foregroundColor: Colors.white,
      ),
      body: Stack(
        children: [
          GoogleMap(
            initialCameraPosition: CameraPosition(
              target: _currentBusLocation,
              zoom: 15,
            ),
            markers: {
              if (_busMarker != null) _busMarker!,
              ..._stopMarkers,
            },
            polylines: _routeLines,
            onMapCreated: (controller) => _mapController = controller,
            myLocationButtonEnabled: true,
          ),

          // Bottom info card
          Positioned(
            bottom: 0, left: 0, right: 0,
            child: Container(
              padding: const EdgeInsets.all(20),
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                boxShadow: [BoxShadow(blurRadius: 10, color: Colors.black12)],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _InfoTile(
                        label: 'Speed',
                        value: '${_busSpeed.toStringAsFixed(0)} km/h',
                        icon: Icons.speed,
                      ),
                      if (widget.stopId != null)
                        _InfoTile(
                          label: 'Stops Away',
                          value: '$_stopsAway stops',
                          icon: Icons.place,
                        ),
                      _InfoTile(
                        label: 'ETA',
                        value: _eta,
                        icon: Icons.access_time,
                      ),
                      _InfoTile(
                        label: 'Status',
                        value: _busSpeed > 0 ? 'Moving' : 'Stopped',
                        icon: Icons.circle,
                        color: _busSpeed > 0 ? Colors.green : Colors.orange,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoTile extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  const _InfoTile({
    required this.label,
    required this.value,
    required this.icon,
    this.color = const Color(0xFF1E6BFF),
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Icon(icon, color: color, size: 24),
        const SizedBox(height: 4),
        Text(value,
            style: const TextStyle(
                fontWeight: FontWeight.bold, fontSize: 16)),
        Text(label,
            style: const TextStyle(color: Colors.grey, fontSize: 12)),
      ],
    );
  }
}
