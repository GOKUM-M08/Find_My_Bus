import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'tracking_screen.dart';

class StopsScreen extends StatefulWidget {
  final String busId;
  final String busNumber;
  final String schoolName;

  const StopsScreen({
    super.key,
    required this.busId,
    required this.busNumber,
    required this.schoolName,
  });

  @override
  State<StopsScreen> createState() => _StopsScreenState();
}

class _StopsScreenState extends State<StopsScreen> {
  final supabase = Supabase.instance.client;

  List<Map<String, dynamic>> _stops = [];
  bool _loading = true;
  int _currentStopIndex = -1; // -1 = unknown / not yet moving
  bool _busIsLive = false;
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _loadStops();
    // Refresh the bus's position (and which stop it's near) every
    // 15 seconds, so the "passed / current / upcoming" state stays
    // accurate while this screen is open — same idea as WIMT
    // periodically refreshing train position.
    _refreshTimer = Timer.periodic(
      const Duration(seconds: 15),
      (_) => _refreshBusPosition(),
    );
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadStops() async {
    final routeResult = await supabase
        .from('routes')
        .select('id')
        .eq('bus_id', widget.busId)
        .maybeSingle();

    if (routeResult == null) {
      setState(() => _loading = false);
      return;
    }

    final stopsResult = await supabase
        .from('stops')
        .select('id, stop_name, latitude, longitude, stop_order, expected_time')
        .eq('route_id', routeResult['id'])
        .order('stop_order');

    setState(() {
      _stops = List<Map<String, dynamic>>.from(stopsResult);
      _loading = false;
    });

    await _refreshBusPosition();
  }

  Future<void> _refreshBusPosition() async {
    if (_stops.isEmpty) return;
    final locResult = await supabase
        .from('live_location')
        .select('latitude, longitude, timestamp')
        .eq('bus_id', widget.busId)
        .maybeSingle();

    if (locResult == null) {
      if (mounted) setState(() => _busIsLive = false);
      return;
    }

    // Only treat the bus as "live" if it actually broadcast recently —
    // otherwise a bus that stopped hours/days ago would show as active
    // forever, since the row never gets deleted, only overwritten.
    final rawTimestamp = locResult['timestamp'];
    if (rawTimestamp == null) {
      if (mounted) setState(() => _busIsLive = false);
      return;
    }
    final lastUpdate = DateTime.parse(rawTimestamp).toUtc();
    final secondsAgo = DateTime.now().toUtc().difference(lastUpdate).inSeconds;
    final isRecent = secondsAgo < 60; // stale after 1 minute of silence

    if (!isRecent) {
      if (mounted) setState(() => _busIsLive = false);
      return;
    }

    final busLat = (locResult['latitude'] as num).toDouble();
    final busLon = (locResult['longitude'] as num).toDouble();

    // Find the stop nearest to the bus's current position — same
    // approach as the backend's ETA calculation — and treat every
    // stop before it as already passed.
    double minDistance = double.infinity;
    int nearestIndex = 0;
    for (int i = 0; i < _stops.length; i++) {
      final d = _haversine(
        busLat, busLon,
        (_stops[i]['latitude'] as num).toDouble(),
        (_stops[i]['longitude'] as num).toDouble(),
      );
      if (d < minDistance) {
        minDistance = d;
        nearestIndex = i;
      }
    }

    if (!mounted) return;
    setState(() {
      _currentStopIndex = nearestIndex;
      _busIsLive = true;
    });
  }

  double _haversine(double lat1, double lon1, double lat2, double lon2) {
    const r = 6371.0;
    final dLat = _deg2rad(lat2 - lat1);
    final dLon = _deg2rad(lon2 - lon1);
    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(_deg2rad(lat1)) *
            cos(_deg2rad(lat2)) *
            sin(dLon / 2) *
            sin(dLon / 2);
    final c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return r * c;
  }

  double _deg2rad(double deg) => deg * (pi / 180);

  void _viewOnMap({String? stopId}) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => TrackingScreen(
          busId: widget.busId,
          busNumber: widget.busNumber,
          stopId: stopId,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF3F5F9),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E6BFF),
        foregroundColor: Colors.white,
        elevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.busNumber,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
            ),
            if (widget.schoolName.isNotEmpty)
              Text(
                widget.schoolName,
                style: const TextStyle(fontSize: 13, color: Colors.white70),
              ),
          ],
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _stops.isEmpty
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(32),
                    child: Text(
                      'No stops have been set up for this bus yet.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey),
                    ),
                  ),
                )
              : Column(
                  children: [
                    if (_busIsLive)
                      Container(
                        width: double.infinity,
                        color: Colors.green.shade50,
                        padding: const EdgeInsets.symmetric(
                            vertical: 8, horizontal: 16),
                        child: const Row(
                          children: [
                            Icon(Icons.circle, color: Colors.green, size: 10),
                            SizedBox(width: 8),
                            Text(
                              'Bus is live — updated moments ago',
                              style: TextStyle(
                                color: Colors.green,
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                    Expanded(
                      child: ListView.builder(
                        padding: const EdgeInsets.symmetric(
                            vertical: 12, horizontal: 16),
                        itemCount: _stops.length,
                        itemBuilder: (context, index) =>
                            _buildStopRow(index),
                      ),
                    ),
                    _buildBottomButton(),
                  ],
                ),
    );
  }

  Widget _buildStopRow(int index) {
    final stop = _stops[index];
    final isPassed = _currentStopIndex >= 0 && index < _currentStopIndex;
    final isCurrent = _currentStopIndex == index;
    final isLast = index == _stops.length - 1;

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Timeline dot + connecting line
          Column(
            children: [
              _StopDot(isPassed: isPassed, isCurrent: isCurrent),
              if (!isLast)
                Expanded(
                  child: Container(
                    width: 3,
                    color: isPassed
                        ? const Color(0xFF1E6BFF)
                        : Colors.grey.shade300,
                  ),
                ),
            ],
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 24),
              child: InkWell(
                onTap: () => _viewOnMap(stopId: stop['id']),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            stop['stop_name'] ?? '',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: isCurrent
                                  ? FontWeight.bold
                                  : FontWeight.w600,
                              color: isPassed
                                  ? Colors.grey
                                  : Colors.black87,
                            ),
                          ),
                          if (isCurrent)
                            const Padding(
                              padding: EdgeInsets.only(top: 2),
                              child: Text(
                                'Bus is near here',
                                style: TextStyle(
                                  color: Colors.green,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    if (stop['expected_time'] != null)
                      Text(
                        stop['expected_time'],
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: isPassed ? Colors.grey : Colors.black54,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomButton() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: ElevatedButton.icon(
          onPressed: () => _viewOnMap(),
          icon: const Icon(Icons.map_outlined),
          label: const Text('View on map'),
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF1E6BFF),
            foregroundColor: Colors.white,
            minimumSize: const Size(double.infinity, 48),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        ),
      ),
    );
  }
}

class _StopDot extends StatelessWidget {
  final bool isPassed;
  final bool isCurrent;

  const _StopDot({required this.isPassed, required this.isCurrent});

  @override
  Widget build(BuildContext context) {
    if (isCurrent) {
      return Container(
        width: 20,
        height: 20,
        decoration: const BoxDecoration(
          color: Colors.green,
          shape: BoxShape.circle,
        ),
        child: const Icon(Icons.directions_bus, color: Colors.white, size: 12),
      );
    }
    return Container(
      width: 14,
      height: 14,
      margin: const EdgeInsets.symmetric(vertical: 3),
      decoration: BoxDecoration(
        color: isPassed ? const Color(0xFF1E6BFF) : Colors.white,
        shape: BoxShape.circle,
        border: Border.all(
          color: isPassed ? const Color(0xFF1E6BFF) : Colors.grey.shade400,
          width: 2,
        ),
      ),
      child: isPassed
          ? const Icon(Icons.check, color: Colors.white, size: 10)
          : null,
    );
  }
}