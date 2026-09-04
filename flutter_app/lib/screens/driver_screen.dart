import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'config.dart';

class DriverScreen extends StatefulWidget {
  final String busId;
  final String deviceId;
  final String busNumber;

  const DriverScreen({
    super.key,
    required this.busId,
    required this.deviceId,
    required this.busNumber,
  });

  @override
  State<DriverScreen> createState() => _DriverScreenState();
}

class _DriverScreenState extends State<DriverScreen> {
  Timer? _timer;
  bool _isTracking = false;
  String _status = "Tap Start to begin sending location";
  double _currentLat = 0;
  double _currentLon = 0;
  double _currentSpeed = 0;
  int _updateCount = 0;

    final supabase = Supabase.instance.client;

  @override
  void initState() {
    super.initState();
    // Auto-start broadcasting as soon as this screen opens, so the
    // driver doesn't have to remember to tap "Start" — the bus shows
    // as active the moment they open the app.
    _startTracking();
  }
  Future<bool> _checkPermission() async {
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.deniedForever) {
      if (mounted) {
        setState(() => _status = "Location permission denied. Enable in settings.");
      }
      return false;
    }
    return true;
  }

  void _startTracking() async {
    bool hasPermission = await _checkPermission();
    if (!hasPermission || !mounted) return;

    setState(() {
      _isTracking = true;
      _status = "Starting...";
      _updateCount = 0;
    });

    // Send location immediately on start
    await _sendLocation();

    // Then send every 10 seconds
    _timer = Timer.periodic(const Duration(seconds: 4), (_) async {
      await _sendLocation();
    });
  }

  Future<void> _sendLocation() async {
    try {
      Position pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      // Send to Supabase live_location table
      await supabase.from('live_location').upsert({
        'bus_id': widget.busId,
        'device_id': widget.deviceId,
        'latitude': pos.latitude,
        'longitude': pos.longitude,
        'speed': (pos.speed * 3.6).clamp(0, 200), // m/s → km/h
        'timestamp': DateTime.now().toIso8601String(),
      }, onConflict: 'bus_id');

      // Also save to history
      await supabase.from('location_history').insert({
        'bus_id': widget.busId,
        'latitude': pos.latitude,
        'longitude': pos.longitude,
        'speed': (pos.speed * 3.6).clamp(0, 200),
      });

      // Post to backend internal broadcast endpoint to trigger FCM topic notifications
      try {
        final speedKmh = (pos.speed * 3.6).clamp(0.0, 200.0);
        await http.post(
          Uri.parse('$kBackendBaseUrl/internal/broadcast/${widget.busId}'),
          headers: {'Content-Type': 'application/json'},
          body: json.encode({
            'latitude': pos.latitude,
            'longitude': pos.longitude,
            'speed': speedKmh,
            'device_id': widget.deviceId,
          }),
        ).timeout(const Duration(seconds: 5));
      } catch (broadcastErr) {
        debugPrint('Backend broadcast POST failed: $broadcastErr');
      }

      if (!mounted) return;
      setState(() {
        _currentLat = pos.latitude;
        _currentLon = pos.longitude;
        _currentSpeed = pos.speed * 3.6;
        _updateCount++;
        _status = "Live — update #$_updateCount sent";
      });
    } catch (e) {
      if (mounted) {
        setState(() => _status = "Error: $e");
      }
    }
  }

  void _stopTracking() {
    _timer?.cancel();
    setState(() {
      _isTracking = false;
      _status = "Stopped. Tap Start to resume.";
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F172A),
        foregroundColor: Colors.white,
        title: Text('Driver — Bus ${widget.busNumber}'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            // Status Card
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: _isTracking
                    ? const Color(0xFF166534)
                    : const Color(0xFF1E293B),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                children: [
                  Icon(
                    _isTracking ? Icons.wifi_tethering : Icons.wifi_tethering_off,
                    color: _isTracking ? Colors.greenAccent : Colors.grey,
                    size: 56,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    _isTracking ? 'BROADCASTING LIVE' : 'OFFLINE',
                    style: TextStyle(
                      color: _isTracking ? Colors.greenAccent : Colors.grey,
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                      letterSpacing: 2,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _status,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // Live Stats
            if (_isTracking) ...[
              Row(
                children: [
                  _StatCard(
                    label: 'Speed',
                    value: '${_currentSpeed.toStringAsFixed(0)} km/h',
                    icon: Icons.speed,
                  ),
                  const SizedBox(width: 12),
                  _StatCard(
                    label: 'Updates',
                    value: '$_updateCount sent',
                    icon: Icons.cloud_upload,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  _StatCard(
                    label: 'Latitude',
                    value: _currentLat.toStringAsFixed(5),
                    icon: Icons.location_on,
                  ),
                  const SizedBox(width: 12),
                  _StatCard(
                    label: 'Longitude',
                    value: _currentLon.toStringAsFixed(5),
                    icon: Icons.location_on,
                  ),
                ],
              ),
              const SizedBox(height: 20),
            ],

            const Spacer(),

            // Interval Info
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFF1E293B),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Row(
                children: [
                  Icon(Icons.info_outline, color: Colors.blue, size: 18),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Location sent every 10 seconds. '
                      'Parents see your bus moving live on their map.',
                      style: TextStyle(color: Colors.white60, fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // Start / Stop Button
            SizedBox(
              width: double.infinity,
              height: 60,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor:
                      _isTracking ? Colors.red : const Color(0xFF1E6BFF),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                onPressed: _isTracking ? _stopTracking : _startTracking,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(_isTracking ? Icons.stop : Icons.play_arrow, size: 24),
                    const SizedBox(width: 10),
                    Text(
                      _isTracking ? 'Stop Broadcasting' : 'Start Broadcasting',
                      style: const TextStyle(
                          fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;

  const _StatCard({
    required this.label,
    required this.value,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFF1E293B),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: const Color(0xFF1E6BFF), size: 20),
            const SizedBox(height: 8),
            Text(value,
                style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 15)),
            Text(label,
                style: const TextStyle(color: Colors.grey, fontSize: 12)),
          ],
        ),
      ),
    );
  }
}