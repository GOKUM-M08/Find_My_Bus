import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart' hide Path;
import 'package:supabase_flutter/supabase_flutter.dart';

import 'config.dart';

// Palette matching home_screen.dart & main.dart
const Color PRIMARY_BLUE = Color(0xFF0052CC);
const Color SECONDARY_BLUE = Color(0xFF1E6BFF);
const Color LIGHT_BLUE = Color(0xFFE8F0FE);
const Color BACKGROUND_BLUE = Color(0xFFF7F9FC);

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

class _TrackingScreenState extends State<TrackingScreen>
    with TickerProviderStateMixin {
  final MapController _mapController = MapController();
  Marker? _busMarker;
  List<LatLng> _routePoints = [];
  List<Marker> _stopMarkers = [];
  List<Map<String, dynamic>> _rawStops = [];
  String _routeName = '';

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

      final stops = List<Map<String, dynamic>>.from(routes['stops']);
      stops.sort((a, b) => (a['stop_order'] as int).compareTo(b['stop_order'] as int));
      _rawStops = stops;
      _routeName = routes['route_name'] ?? 'School Route';

      for (var stop in stops) {
        LatLng pos = LatLng(stop['latitude'], stop['longitude']);
        routePoints.add(pos);
      }

      setState(() {
        _routePoints = routePoints;
        _rebuildStopMarkers();
        _updateBusMarker();
      });
    }
  }

  void _rebuildStopMarkers() {
    if (_rawStops.isEmpty) return;

    List<Marker> stopMarkers = [];
    for (int i = 0; i < _rawStops.length; i++) {
      final stop = _rawStops[i];
      final pos = LatLng(stop['latitude'], stop['longitude']);
      final isTargetStop = widget.stopId != null && stop['id'].toString() == widget.stopId;
      final stopNumber = i + 1;

      stopMarkers.add(
        Marker(
          point: pos,
          width: 32,
          height: 32,
          alignment: Alignment.center,
          child: GestureDetector(
            onTap: () => _showStopDetailsSheet(stop, stopNumber, isTargetStop),
            child: _StopNodeMarker(
              stopNumber: stopNumber,
              stopName: stop['stop_name'] ?? 'Stop #$stopNumber',
              isTarget: isTargetStop,
            ),
          ),
        ),
      );
    }

    setState(() {
      _stopMarkers = stopMarkers;
    });
  }

  void _showStopDetailsSheet(Map<String, dynamic> stop, int stopOrder, bool isTarget) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    radius: 22,
                    backgroundColor: isTarget ? Colors.red.shade50 : LIGHT_BLUE,
                    child: Icon(
                      isTarget ? Icons.star_rounded : Icons.directions_bus_rounded,
                      color: isTarget ? Colors.red.shade600 : PRIMARY_BLUE,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          stop['stop_name'] ?? 'Stop #$stopOrder',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Stop Order #$stopOrder • Scheduled: ${stop['expected_time'] ?? 'N/A'}',
                          style: const TextStyle(fontSize: 12, color: Colors.blueGrey),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              if (!isTarget)
                SizedBox(
                  width: double.infinity,
                  height: 44,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: PRIMARY_BLUE,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: () {
                      Navigator.pop(context);
                      _fetchETA(stop['id'].toString());
                    },
                    icon: const Icon(Icons.timer_outlined, size: 18),
                    label: const Text('Track Live ETA for this Stop'),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  void _subscribeToLiveLocation() {
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
    final isMoving = _isLive && _busSpeed > 1;
    final statusText = !_isLive
        ? 'Offline • Waiting for update'
        : (isMoving ? 'Moving • ${_busSpeed.toStringAsFixed(0)} km/h' : 'Stopped at location');
    final statusColor = !_isLive
        ? Colors.grey.shade700
        : (isMoving ? const Color(0xFF10B981) : const Color(0xFFF59E0B));

    _busMarker = Marker(
      point: _currentBusLocation,
      width: 48,
      height: 48,
      alignment: Alignment.center,
      child: GestureDetector(
        onTap: () => _showBusDetailsSheet(),
        child: Stack(
          alignment: Alignment.center,
          clipBehavior: Clip.none,
          children: [
            // Vehicle Pin Avatar anchored precisely at geometric center (24, 24)
            _BusVehicleAvatar(
              isLive: _isLive,
              isMoving: isMoving,
              statusColor: statusColor,
            ),

            // Speech Bubble Callout Card floated above avatar via clipBehavior
            Positioned(
              bottom: 46,
              child: _BusCalloutCard(
                busNumber: widget.busNumber,
                routeName: _routeName.isNotEmpty ? _routeName : 'School Route',
                statusText: statusText,
                statusColor: statusColor,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showBusDetailsSheet() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        final isMoving = _isLive && _busSpeed > 1;
        final statusText = !_isLive ? 'Offline' : (isMoving ? 'Moving' : 'Stopped');
        final statusColor = !_isLive
            ? Colors.grey
            : (isMoving ? Colors.green.shade600 : Colors.amber.shade700);

        return Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    radius: 24,
                    backgroundColor: LIGHT_BLUE,
                    child: const Icon(Icons.directions_bus_rounded, color: PRIMARY_BLUE, size: 28),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Bus ${widget.busNumber}',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                        ),
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(color: statusColor, shape: BoxShape.circle),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              statusText,
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: statusColor),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              const Divider(),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _InfoDetailColumn(label: 'CURRENT SPEED', value: '${_busSpeed.toStringAsFixed(0)} km/h'),
                  _InfoDetailColumn(label: 'STOPS REMAINING', value: '$_stopsAway stops'),
                  _InfoDetailColumn(label: 'TARGET ETA', value: _eta),
                ],
              ),
              const SizedBox(height: 12),
            ],
          ),
        );
      },
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
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _currentBusLocation,
              initialZoom: 14,
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.example.bustrack',
              ),
              PolylineLayer(
                polylines: [
                  // Outer border stroke
                  Polyline(
                    points: _routePoints,
                    color: const Color(0xFF003D99).withOpacity(0.3),
                    strokeWidth: 8,
                  ),
                  // Inner route line matching screenshot
                  Polyline(
                    points: _routePoints,
                    color: SECONDARY_BLUE,
                    strokeWidth: 5,
                  ),
                ],
              ),
              MarkerLayer(
                markers: [
                  ..._stopMarkers,
                  if (_busMarker != null) _busMarker!,
                ],
              ),
            ],
          ),

          // Top Left Floating Back/Close Circular Button (matching screenshot (X))
          Positioned(
            top: 40,
            left: 16,
            child: GestureDetector(
              onTap: () => Navigator.pop(context),
              child: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.55),
                  shape: BoxShape.circle,
                  boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 4)],
                ),
                child: const Icon(Icons.close_rounded, color: Colors.white, size: 22),
              ),
            ),
          ),

          // Floating Map Camera Controls
          Positioned(
            right: 14,
            top: 40,
            child: Column(
              children: [
                FloatingActionButton.small(
                  heroTag: 'recenter_bus',
                  backgroundColor: Colors.white,
                  foregroundColor: PRIMARY_BLUE,
                  elevation: 4,
                  onPressed: () {
                    _mapController.move(_currentBusLocation, 15.5);
                  },
                  child: const Icon(Icons.my_location_rounded, size: 20),
                ),
                const SizedBox(height: 8),
                FloatingActionButton.small(
                  heroTag: 'fit_bounds',
                  backgroundColor: Colors.white,
                  foregroundColor: PRIMARY_BLUE,
                  elevation: 4,
                  onPressed: () {
                    if (_routePoints.isNotEmpty) {
                      _mapController.fitCamera(
                        CameraFit.bounds(
                          bounds: LatLngBounds.fromPoints([_currentBusLocation, ..._routePoints]),
                          padding: const EdgeInsets.all(50),
                        ),
                      );
                    }
                  },
                  child: const Icon(Icons.zoom_out_map_rounded, size: 20),
                ),
              ],
            ),
          ),

          // Bottom Template Status Bar (matching screenshot layout)
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: const EdgeInsets.fromLTRB(20, 16, 16, 24),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.12),
                    blurRadius: 10,
                    offset: const Offset(0, -3),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          !_isLive
                              ? 'Bus Offline • Waiting for update'
                              : (_busSpeed > 1
                                  ? 'Moving at ${_busSpeed.toStringAsFixed(0)} km/h'
                                  : 'Stopped at location'),
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                            color: Color(0xFF1E293B),
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          widget.stopId != null ? 'ETA: $_eta • $_stopsAway stops away' : 'Updated few seconds ago',
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.blueGrey,
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Floating Circular Refresh Action Button (matching bottom right blue circle button in screenshot)
                  GestureDetector(
                    onTap: () {
                      _checkLiveStatus();
                      if (widget.stopId != null) _fetchETA(widget.stopId!);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Refreshing live location...'),
                          duration: Duration(seconds: 1),
                        ),
                      );
                    },
                    child: Container(
                      width: 48,
                      height: 48,
                      decoration: const BoxDecoration(
                        color: PRIMARY_BLUE,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black26,
                            blurRadius: 6,
                            offset: Offset(0, 2),
                          ),
                        ],
                      ),
                      child: const Icon(Icons.refresh_rounded, color: Colors.white, size: 24),
                    ),
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

// 💬 Floating Speech Bubble Callout Card above Bus Pin (matching template screenshot)
class _BusCalloutCard extends StatelessWidget {
  final String busNumber;
  final String routeName;
  final String statusText;
  final Color statusColor;

  const _BusCalloutCard({
    required this.busNumber,
    required this.routeName,
    required this.statusText,
    required this.statusColor,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(8),
            boxShadow: const [
              BoxShadow(
                color: Colors.black26,
                blurRadius: 8,
                offset: Offset(0, 3),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Bus $busNumber: $routeName',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                  color: Colors.black87,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                statusText,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: statusColor,
                ),
              ),
            ],
          ),
        ),
        // Speech Bubble Pointer Arrow Tip pointing down
        CustomPaint(
          size: const Size(12, 6),
          painter: _TrianglePointerPainter(color: Colors.white),
        ),
      ],
    );
  }
}

class _TrianglePointerPainter extends CustomPainter {
  final Color color;
  _TrianglePointerPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width / 2, size.height)
      ..lineTo(size.width, 0)
      ..close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _BusVehicleAvatar extends StatefulWidget {
  final bool isLive;
  final bool isMoving;
  final Color statusColor;

  const _BusVehicleAvatar({
    required this.isLive,
    required this.isMoving,
    required this.statusColor,
  });

  @override
  State<_BusVehicleAvatar> createState() => _BusVehicleAvatarState();
}

class _BusVehicleAvatarState extends State<_BusVehicleAvatar>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat();
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: [
        if (widget.isLive)
          AnimatedBuilder(
            animation: _pulseController,
            builder: (context, _) {
              final scale = 1.0 + (_pulseController.value * 0.4);
              final opacity = (1.0 - _pulseController.value).clamp(0.0, 1.0);
              return Transform.scale(
                scale: scale,
                child: Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: widget.statusColor.withOpacity(opacity * 0.35),
                  ),
                ),
              );
            },
          ),
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: PRIMARY_BLUE,
            border: Border.all(color: Colors.white, width: 2.5),
            boxShadow: const [
              BoxShadow(
                color: Colors.black26,
                blurRadius: 6,
                offset: Offset(0, 2),
              ),
            ],
          ),
          child: const Center(
            child: Icon(
              Icons.directions_bus_rounded,
              color: Colors.white,
              size: 20,
            ),
          ),
        ),
      ],
    );
  }
}

class _StopNodeMarker extends StatelessWidget {
  final int stopNumber;
  final String stopName;
  final bool isTarget;

  const _StopNodeMarker({
    required this.stopNumber,
    required this.stopName,
    required this.isTarget,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 28,
      height: 28,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: isTarget ? const Color(0xFFDC2626) : PRIMARY_BLUE,
        border: Border.all(color: Colors.white, width: 2),
        boxShadow: const [
          BoxShadow(
            color: Colors.black26,
            blurRadius: 4,
            offset: Offset(0, 1),
          ),
        ],
      ),
      child: Center(
        child: Icon(
          isTarget ? Icons.star_rounded : Icons.directions_bus_rounded,
          color: Colors.white,
          size: 14,
        ),
      ),
    );
  }
}

class _InfoDetailColumn extends StatelessWidget {
  final String label;
  final String value;

  const _InfoDetailColumn({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 10, color: Colors.grey, fontWeight: FontWeight.bold, letterSpacing: 0.5),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: PRIMARY_BLUE),
        ),
      ],
    );
  }
}
