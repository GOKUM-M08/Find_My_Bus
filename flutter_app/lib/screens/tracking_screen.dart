import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' hide Path;
import 'package:provider/provider.dart';

import '../services/api_client.dart';
import '../services/language_service.dart';
import '../services/notification_service.dart';
import '../services/session_store.dart';
import '../services/voice_assistant_service.dart';
import '../utils/time_utils.dart';
import '../widgets/voice_assistant_sheet.dart';

// Palette matching parent screens
const Color PRIMARY_BLUE = Color(0xFF0052CC);
const Color SECONDARY_BLUE = Color(0xFF1E6BFF);
const Color LIGHT_BLUE = Color(0xFFE8F0FE);
const Color BACKGROUND_BLUE = Color(0xFFF7F9FC);

class TrackingScreen extends StatefulWidget {
  final String busId;
  final String busNumber;
  final String? stopId;
  final double? initialBusLat;
  final double? initialBusLon;

  const TrackingScreen({
    super.key,
    required this.busId,
    required this.busNumber,
    this.stopId,
    this.initialBusLat,
    this.initialBusLon,
  });

  @override
  State<TrackingScreen> createState() => _TrackingScreenState();
}

class _TrackingScreenState extends State<TrackingScreen>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  final MapController _mapController = MapController();
  final LanguageService _languageService = LanguageService();

  Marker? _busMarker;
  List<Marker> _stopMarkers = [];
  List<Map<String, dynamic>> _rawStops = [];
  String _routeName = '';

  StreamSubscription? _fcmSub;
  Timer? _pollTimer;
  Timer? _etaTimer;

  LatLng _currentBusLocation = const LatLng(13.0827, 80.2707);
  double _busSpeed = 0;
  String _eta = "Calculating...";
  int _stopsAway = 0;

  bool _isLive = false;
  bool _isReconnecting = false;
  bool _hasAutoNavigated = false;
  bool _isRefreshing = false;
  int _pollIntervalSeconds = 5;
  bool _isScreenVisible = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    if (widget.initialBusLat != null &&
        widget.initialBusLon != null &&
        widget.initialBusLat != 0.0 &&
        widget.initialBusLon != 0.0) {
      _currentBusLocation = LatLng(widget.initialBusLat!, widget.initialBusLon!);
    }
    WidgetsBinding.instance.addObserver(this);
    _languageService.addListener(_onLanguageChanged);

    _fcmSub = NotificationService().onForegroundMessage.listen((message) {
      if (!mounted) return;
      final title = message.notification?.title ?? 'Bus Update';
      final body = message.notification?.body ?? '';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.notifications_active, color: Colors.white),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
                    if (body.isNotEmpty) Text(body, style: const TextStyle(fontSize: 12)),
                  ],
                ),
              ),
            ],
          ),
          backgroundColor: PRIMARY_BLUE,
          duration: const Duration(seconds: 4),
          behavior: SnackBarBehavior.floating,
        ),
      );
      if (body.isNotEmpty) {
        VoiceAssistantService().speak(body);
      }
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadRoute();
      _pollLiveLocation();
      _schedulePoll();
      _initETA();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _languageService.removeListener(_onLanguageChanged);
    _fcmSub?.cancel();
    _pollTimer?.cancel();
    _etaTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _isScreenVisible = true;
      _schedulePoll(immediate: true);
    } else if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      _isScreenVisible = false;
      _pollTimer?.cancel();
    }
  }

  void _onLanguageChanged() {
    if (mounted) setState(() {});
  }

  void _schedulePoll({bool immediate = false}) {
    _pollTimer?.cancel();
    if (!_isScreenVisible || !mounted) return;

    if (immediate) {
      _pollLiveLocation();
    } else {
      _pollTimer = Timer(Duration(seconds: _pollIntervalSeconds), () async {
        await _pollLiveLocation();
        _schedulePoll();
      });
    }
  }

  Future<void> _initETA() async {
    final targetStopId = widget.stopId;
    if (targetStopId != null && targetStopId.isNotEmpty) {
      _fetchETA(targetStopId);
      _etaTimer = Timer.periodic(const Duration(seconds: 15), (_) {
        _fetchETA(targetStopId);
      });
    } else {
      setState(() {
        _eta = "Select a stop for ETA";
      });
    }
  }

  Future<void> _loadRoute() async {
    if (!mounted) return;
    final api = context.read<SessionController>().apiClient;

    try {
      final res = await api.get('/api/parent/bus/${widget.busId}/route');
      if (res is List && res.isNotEmpty) {
        final route = res[0];
        if (route is Map && route['stops'] is List) {
          final stops = List<Map<String, dynamic>>.from(route['stops']);
          _rawStops = stops;
          _routeName = route['route_name']?.toString() ?? 'School Route';

          final points = <LatLng>[];
          for (final stop in stops) {
            final lat = (stop['latitude'] as num?)?.toDouble() ?? 0.0;
            final lon = (stop['longitude'] as num?)?.toDouble() ?? 0.0;
            if (lat != 0.0 && lon != 0.0) {
              points.add(LatLng(lat, lon));
            }
          }

          if (!mounted) return;
          setState(() {
            _rebuildStopMarkers();
            _updateBusMarker();
          });

          if (points.isNotEmpty && _currentBusLocation.latitude == 13.0827) {
            _currentBusLocation = points.first;
            _updateBusMarker();
          }
        }
      }
    } on ApiException catch (e) {
      if (!mounted) return;
      if (e.kind == ApiExceptionKind.unauthorized) {
        context.read<SessionController>().logout(reason: 'Please log in again');
      } else if (e.kind == ApiExceptionKind.forbidden) {
        setState(() {
          _errorMessage = _languageService.getText('bus_not_linked');
        });
      }
    } catch (_) {}
  }

  Future<void> _pollLiveLocation({bool immediateMove = false}) async {
    if (!mounted || !_isScreenVisible) return;
    final session = context.read<SessionController>();
    final api = session.apiClient;

    try {
      final locRes = await api.get('/api/parent/bus/${widget.busId}/live');
      if (!mounted) return;

      if (locRes == null || locRes is! Map) {
        setState(() {
          _isLive = false;
          _isReconnecting = false;
          _pollIntervalSeconds = 5;
          _updateBusMarker();
        });
        return;
      }

      final live = isLiveTimestamp(locRes['timestamp']?.toString());

      final lat = (locRes['latitude'] as num?)?.toDouble();
      final lon = (locRes['longitude'] as num?)?.toDouble();
      final speed = (locRes['speed'] as num?)?.toDouble() ?? 0.0;

      setState(() {
        _isLive = live;
        _isReconnecting = false;
        _pollIntervalSeconds = 5; // reset backoff on success
        if (lat != null && lon != null && lat != 0.0 && lon != 0.0) {
          final newLoc = LatLng(lat, lon);
          _currentBusLocation = newLoc;
          _busSpeed = speed;

          // Automatically navigate / center to bus on initial entry or manual refresh
          if (!_hasAutoNavigated || immediateMove) {
            _hasAutoNavigated = true;
            try {
              _mapController.move(newLoc, 16.0);
            } catch (_) {}
          }
        }
        if (!live && widget.stopId != null) {
          _eta = "Bus offline";
        }
        _updateBusMarker();
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      if (e.kind == ApiExceptionKind.unauthorized) {
        session.logout(reason: 'Please log in again');
        return;
      } else if (e.kind == ApiExceptionKind.forbidden) {
        setState(() {
          _errorMessage = _languageService.getText('bus_not_linked');
        });
        return;
      }
      _handlePollBackoff();
    } catch (_) {
      _handlePollBackoff();
    }
  }

  Future<void> _refreshTracking() async {
    setState(() => _isRefreshing = true);
    await Future.wait([
      _pollLiveLocation(immediateMove: true),
      if (widget.stopId != null && widget.stopId!.isNotEmpty)
        _fetchETA(widget.stopId!),
    ]);
    if (mounted) {
      setState(() => _isRefreshing = false);
    }
  }

  void _handlePollBackoff() {
    if (!mounted) return;
    setState(() {
      _isReconnecting = true;
      _pollIntervalSeconds = min(_pollIntervalSeconds * 2, 30);
    });
  }

  Future<void> _fetchETA(String stopId) async {
    if (!mounted) return;
    final api = context.read<SessionController>().apiClient;
    try {
      final data = await api.get('/api/parent/bus/${widget.busId}/eta/$stopId');
      if (!mounted) return;
      if (data is Map) {
        setState(() {
          _eta = data['eta']?.toString() ?? 'Calculating...';
          _stopsAway = (data['stops_away'] as num?)?.toInt() ?? 0;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _eta = 'Unavailable');
      }
    }
  }

  void _rebuildStopMarkers() {
    if (_rawStops.isEmpty) return;

    List<Marker> stopMarkers = [];
    for (int i = 0; i < _rawStops.length; i++) {
      final stop = _rawStops[i];
      final pos = LatLng(
        (stop['latitude'] as num?)?.toDouble() ?? 0.0,
        (stop['longitude'] as num?)?.toDouble() ?? 0.0,
      );
      if (pos.latitude == 0.0 && pos.longitude == 0.0) continue;

      final isTargetStop = widget.stopId != null && stop['id'].toString() == widget.stopId;
      final stopNumber = i + 1;

      stopMarkers.add(
        Marker(
          point: pos,
          width: 34,
          height: 34,
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
                    child: isTarget
                        ? const Icon(Icons.star_rounded, color: Color(0xFFDC2626), size: 24)
                        : ClipOval(
                            child: Image.asset(
                              'assets/icon/icon.png',
                              width: 22,
                              height: 22,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => const Icon(
                                Icons.directions_bus_rounded,
                                color: PRIMARY_BLUE,
                                size: 20,
                              ),
                            ),
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
            _BusVehicleAvatar(
              isLive: _isLive,
              isMoving: isMoving,
              statusColor: statusColor,
            ),
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
                    child: ClipOval(
                      child: Image.asset(
                        'assets/icon/icon.png',
                        width: 28,
                        height: 28,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => const Icon(
                          Icons.directions_bus_rounded,
                          color: PRIMARY_BLUE,
                          size: 26,
                        ),
                      ),
                    ),
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
                            Text(statusText, style: TextStyle(color: statusColor, fontSize: 13, fontWeight: FontWeight.bold)),
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

  @override
  Widget build(BuildContext context) {
    if (_errorMessage != null) {
      return Scaffold(
        appBar: AppBar(backgroundColor: PRIMARY_BLUE, foregroundColor: Colors.white),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              _errorMessage!,
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
          ),
        ),
      );
    }

    return Scaffold(
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _currentBusLocation,
              initialZoom: (widget.initialBusLat != null && widget.initialBusLon != null) ? 16.0 : 14.0,
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.example.bustrack',
              ),
              MarkerLayer(
                markers: [
                  ..._stopMarkers,
                  if (_busMarker != null) _busMarker!,
                ],
              ),
            ],
          ),

          // Reconnecting Banner
          if (_isReconnecting)
            Positioned(
              top: 40,
              left: 20,
              right: 80,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.amber.shade800,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 4)],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _languageService.getText('reconnecting'),
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ),

          // Close / Back Button
          Positioned(
            top: 40,
            left: 14,
            child: GestureDetector(
              onTap: () => Navigator.pop(context),
              child: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.55),
                  shape: BoxShape.circle,
                  boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 4)],
                ),
                child: const Icon(Icons.close_rounded, color: Colors.white, size: 22),
              ),
            ),
          ),

          // Floating Controls
          Positioned(
            right: 14,
            top: 40,
            child: Column(
              children: [
                FloatingActionButton.small(
                  heroTag: 'voice_assistant_tracking',
                  backgroundColor: PRIMARY_BLUE,
                  foregroundColor: Colors.white,
                  elevation: 4,
                  onPressed: () {
                    VoiceAssistantSheet.show(
                      context,
                      busId: widget.busId,
                      busNumber: widget.busNumber,
                      stopId: widget.stopId,
                    );
                  },
                  child: const Icon(Icons.mic, size: 20),
                ),
                const SizedBox(height: 8),
                FloatingActionButton.small(
                  heroTag: 'refresh_tracking',
                  backgroundColor: Colors.white,
                  foregroundColor: PRIMARY_BLUE,
                  elevation: 4,
                  tooltip: 'Refresh',
                  onPressed: _isRefreshing ? null : _refreshTracking,
                  child: _isRefreshing
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2, color: PRIMARY_BLUE),
                        )
                      : const Icon(Icons.refresh_rounded, size: 20),
                ),
                const SizedBox(height: 8),
                FloatingActionButton.small(
                  heroTag: 'recenter_bus',
                  backgroundColor: Colors.white,
                  foregroundColor: PRIMARY_BLUE,
                  elevation: 4,
                  tooltip: 'Navigate to bus',
                  onPressed: () {
                    _mapController.move(_currentBusLocation, 16.0);
                  },
                  child: const Icon(Icons.my_location_rounded, size: 20),
                ),
                const SizedBox(height: 8),
                FloatingActionButton.small(
                  heroTag: 'fit_bounds',
                  backgroundColor: Colors.white,
                  foregroundColor: PRIMARY_BLUE,
                  elevation: 4,
                  tooltip: 'Fit route',
                  onPressed: () {
                    if (_stopMarkers.isNotEmpty) {
                      final allPoints = [
                        _currentBusLocation,
                        ..._rawStops.map((s) => LatLng(
                              (s['latitude'] as num).toDouble(),
                              (s['longitude'] as num).toDouble(),
                            )),
                      ];
                      _mapController.fitCamera(
                        CameraFit.bounds(
                          bounds: LatLngBounds.fromPoints(allPoints),
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

          // Bottom Status Bar
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
                    color: Colors.black.withValues(alpha: 0.12),
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
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                            color: Color(0xFF1E293B),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: !_isLive
                                    ? Colors.grey.shade500
                                    : (_busSpeed > 1 ? const Color(0xFF10B981) : const Color(0xFFF59E0B)),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                widget.stopId != null ? 'ETA: $_eta' : 'Bus ${widget.busNumber}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 13,
                                  color: Color(0xFF64748B),
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  GestureDetector(
                    onTap: () => _showBusDetailsSheet(),
                    child: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: const BoxDecoration(
                        color: LIGHT_BLUE,
                        shape: BoxShape.circle,
                      ),
                      child: ClipOval(
                        child: Image.asset(
                          'assets/icon/icon.png',
                          width: 24,
                          height: 24,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => const Icon(
                            Icons.directions_bus_rounded,
                            color: PRIMARY_BLUE,
                            size: 24,
                          ),
                        ),
                      ),
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
                    color: widget.statusColor.withValues(alpha: opacity * 0.35),
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
          child: Center(
            child: ClipOval(
              child: Image.asset(
                'assets/icon/icon.png',
                width: 22,
                height: 22,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const Icon(
                  Icons.directions_bus_rounded,
                  color: Colors.white,
                  size: 20,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

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
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        boxShadow: const [
          BoxShadow(
            color: Colors.black26,
            blurRadius: 6,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            'Bus $busNumber',
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
          ),
          Text(
            statusText,
            style: TextStyle(color: statusColor, fontSize: 10, fontWeight: FontWeight.w600),
          ),
        ],
      ),
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
        child: isTarget
            ? const Icon(Icons.star_rounded, color: Colors.white, size: 16)
            : Text(
                '$stopNumber',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
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
