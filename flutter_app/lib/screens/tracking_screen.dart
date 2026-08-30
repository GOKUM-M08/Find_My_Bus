import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'stops_screen.dart';

import 'config.dart';
class TrackingScreen extends StatefulWidget {
  final String busId;
  final String busNumber;
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

  // Supabase Realtime subscription — replaces the old custom WebSocket.
  // The WebSocket only fired when gps_listener.py explicitly called the
  // backend's /internal/broadcast endpoint, which Driver Mode (writing
  // straight to Supabase from the phone) never does — so the map only
  // ever updated once, on load. Subscribing directly to database
  // changes works no matter which path wrote the update.
  StreamSubscription? _liveLocationSub;

  LatLng _currentBusLocation = const LatLng(13.0827, 80.2707);
  double _busSpeed = 0;
  String _eta = "Calculating...";
  int _stopsAway = 0;
  Timer? _etaTimer;

  bool _isLive = false;
  Timer? _liveCheckTimer;

  final supabase = Supabase.instance.client;

  @override
  void initState() {
    super.initState();
    _loadRoute();
    _subscribeToLiveLocation();
    _loadInitialLocation();
    _checkLiveStatus();
    _liveCheckTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      _checkLiveStatus();
    });

    if (widget.stopId != null) {
      _fetchETA(widget.stopId!);
      _etaTimer = Timer.periodic(const Duration(seconds: 30), (_) {
        _fetchETA(widget.stopId!);
      });
    } else {
      _eta = "Select a stop for ETA";
    }
  }

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
      _updateBusMarker();
      if (!live && widget.stopId != null) {
        _eta = "Bus offline";
      }
    });
  }

  Future<void> _loadInitialLocation() async {
    final response = await supabase
        .from('live_location')
        .select()
        .eq('bus_id', widget.busId)
        .maybeSingle();

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
    final routes = await supabase
        .from('routes')
        .select('*, stops(*)')
        .eq('bus_id', widget.busId)
        .maybeSingle();

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

  void _showStopInfo(String title, String subtitle) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(subtitle.isEmpty ? title : '$title — $subtitle'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _subscribeToLiveLocation() {
    // Supabase Realtime: fires automatically on every INSERT/UPDATE to
    // live_location for this bus_id — whether that write came from
    // Driver Mode, the simulator, or real GPS hardware via
    // gps_listener.py. No backend relay needed.
    _liveLocationSub = supabase
        .from('live_location')
        .stream(primaryKey: ['id'])
        .eq('bus_id', widget.busId)
        .listen((rows) {
      if (rows.isEmpty) return;
      final row = rows.first;

      if (row['latitude'] == null || row['longitude'] == null) return;

      setState(() {
        _currentBusLocation = LatLng(
          (row['latitude'] as num).toDouble(),
          (row['longitude'] as num).toDouble(),
        );
        _busSpeed = (row['speed'] as num?)?.toDouble() ?? 0;
        _updateBusMarker();
        _mapController.move(_currentBusLocation, _mapController.camera.zoom);
      });

      if (widget.stopId != null) {
        _fetchETA(widget.stopId!);
      }
    });
  }

  void _updateBusMarker() {
    _busMarker = Marker(
      point: _currentBusLocation,
      width: 58,
      height: 58,
      child: GestureDetector(
        onTap: () => _showStopInfo(
          'Bus ${widget.busNumber}',
          '${_busSpeed.toStringAsFixed(0)} km/h',
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            if (_isLive)
              Container(
                width: 54,
                height: 54,
                decoration: BoxDecoration(
                  color: Colors.green.withOpacity(0.16),
                  shape: BoxShape.circle,
                ),
              ),
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 5)],
              ),
              child: Icon(
                Icons.directions_bus,
                color: _isLive ? Colors.green : Colors.grey,
                size: 32,
              ),
            ),
          ],
        ),
      ),
    );
  }

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
    _liveLocationSub?.cancel();
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
          if (!_isLive)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: Container(
                color: Colors.amber.shade100,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Text(
                  "This bus hasn't sent an update recently.",
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.amber.shade900, fontSize: 13),
                ),
              ),
            ),
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
                        onTap: widget.stopId == null
                            ? () => Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => StopsScreen(
                                      busId: widget.busId,
                                      busNumber: widget.busNumber,
                                      schoolName: '',
                                    ),
                                  ),
                                )
                            : null,
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
  final VoidCallback? onTap;

  const _InfoTile({
    required this.label,
    required this.value,
    required this.icon,
    this.color = const Color(0xFF1E6BFF),
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        child: Column(
          children: [
            Icon(icon, color: color, size: 24),
            const SizedBox(height: 4),
            Text(value,
                style: const TextStyle(
                    fontWeight: FontWeight.bold, fontSize: 16)),
            Text(label,
                style: const TextStyle(color: Colors.grey, fontSize: 12)),
          ],
        ),
      ),
    );
  }
}
