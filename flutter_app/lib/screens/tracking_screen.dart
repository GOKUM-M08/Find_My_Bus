import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
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
  final MapController _mapController = MapController();
  Marker? _busMarker;
  List<LatLng> _routePoints = [];
  List<Marker> _stopMarkers = [];

  WebSocketChannel? _wsChannel;
  LatLng _currentBusLocation = const LatLng(13.0827, 80.2707);
  double _busSpeed = 0;
  String _eta = "Calculating...";
  int _stopsAway = 0;
  Timer? _etaTimer;

  // Whether the bus has broadcast a GPS point recently. Without this,
  // an old row in `live_location` makes the bus look "Moving" forever
  // even after the GPS device has been off for hours.
  bool _isLive = false;
  Timer? _liveCheckTimer;

  final supabase = Supabase.instance.client;

  @override
  void initState() {
    super.initState();
    _loadRoute();
    _connectWebSocket();
    _loadInitialLocation();
    _checkLiveStatus();
    _liveCheckTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      _checkLiveStatus();
    });

    // STEP 11.3 — fetch ETA once immediately, then refresh every 30 seconds.
    if (widget.stopId != null) {
      _fetchETA(widget.stopId!);
      _etaTimer = Timer.periodic(const Duration(seconds: 30), (_) {
        _fetchETA(widget.stopId!);
      });
    } else {
      // No specific stop selected (opened via the general "View on Map"
      // button) — there's nothing to calculate ETA to, so say so instead
      // of leaving the tile stuck on "Calculating..." forever.
      _eta = "Select a stop for ETA";
    }
  }

  // Same freshness check used in stops_screen.dart: a bus is only
  // considered live if it broadcast within the last 60 seconds.
  Future<void> _checkLiveStatus() async {
    final result = await supabase
        .from('live_location')
        .select('timestamp')
        .eq('bus_id', widget.busId)
        .maybeSingle();

    bool live = false;
    if (result != null && result['timestamp'] != null) {
      final lastUpdate = DateTime.parse(result['timestamp']).toUtc();
      final secondsAgo =
          DateTime.now().toUtc().difference(lastUpdate).inSeconds;
      live = secondsAgo < 60;
    }

    if (!mounted) return;
    setState(() {
      _isLive = live;
      if (!live && widget.stopId != null) {
        _eta = "Bus offline";
      }
    });
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
      List<Marker> stopMarkers = [];

      final stops = routes['stops'] as List;
      stops.sort((a, b) => a['stop_order'].compareTo(b['stop_order']));

      for (var stop in stops) {
        LatLng pos = LatLng(stop['latitude'], stop['longitude']);
        routePoints.add(pos);

        stopMarkers.add(Marker(
          point: pos,
          width: 36,
          height: 36,
          child: GestureDetector(
            onTap: () => _showStopInfo(
              stop['stop_name'] ?? 'Stop',
              stop['expected_time'] ?? '',
            ),
            child: const Icon(Icons.location_pin,
                color: Colors.blueAccent, size: 32),
          ),
        ));
      }

      setState(() {
        _routePoints = routePoints;
        _stopMarkers = stopMarkers;
      });
    }
  }

  // flutter_map has no built-in InfoWindow — tapping a marker shows this
  // small snackbar instead (used for both the bus marker and stop pins).
  void _showStopInfo(String title, String subtitle) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(subtitle.isEmpty ? title : '$title — $subtitle'),
        duration: const Duration(seconds: 2),
      ),
    );
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
        _mapController.move(_currentBusLocation, _mapController.camera.zoom);
      });

      // A fresh GPS point just came in — refresh ETA too.
      if (widget.stopId != null) {
        _fetchETA(widget.stopId!);
      }
    });
  }

  void _updateBusMarker() {
    _busMarker = Marker(
      point: _currentBusLocation,
      width: 44,
      height: 44,
      child: GestureDetector(
        onTap: () => _showStopInfo(
          'Bus ${widget.busNumber}',
          '${_busSpeed.toStringAsFixed(0)} km/h',
        ),
        child: const Icon(Icons.directions_bus, color: Colors.green, size: 38),
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
    _etaTimer?.cancel();
    _liveCheckTimer?.cancel();
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
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _currentBusLocation,
              initialZoom: 15,
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                // TODO: set this to your real applicationId from
                // android/app/build.gradle (OSM requires a valid user agent).
                userAgentPackageName: 'com.example.bustrack',
              ),
              PolylineLayer(
                polylines: [
                  Polyline(
                    points: _routePoints,
                    color: const Color(0xFF1E6BFF),
                    strokeWidth: 4,
                  ),
                ],
              ),
              MarkerLayer(
                markers: [
                  if (_busMarker != null) _busMarker!,
                  ..._stopMarkers,
                ],
              ),
            ],
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
                        value: !_isLive
                            ? 'Offline'
                            : (_busSpeed > 1 ? 'Moving' : 'Stopped'),
                        icon: Icons.circle,
                        color: !_isLive
                            ? Colors.grey
                            : (_busSpeed > 1 ? Colors.green : Colors.orange),
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
