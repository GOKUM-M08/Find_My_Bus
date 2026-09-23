import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../widgets/admin_drawer.dart';
import 'route_optimizer_screen.dart';

// Speed threshold above which a bus is flagged as overspeeding.
const double kOverspeedThresholdKmh = 60;

class AdminDashboardScreen extends StatefulWidget {
  final String schoolId;
  final String schoolName;

  const AdminDashboardScreen({
    super.key,
    required this.schoolId,
    required this.schoolName,
  });

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  final supabase = Supabase.instance.client;
  List<Map<String, dynamic>> _buses = [];
  bool _loading = true;
  String? _errorMessage;
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _loadBuses();
    // Refresh speed/live data every 10 seconds so overspeed warnings
    // show up promptly, similar to a real fleet-monitoring dashboard.
    _refreshTimer = Timer.periodic(
      const Duration(seconds: 10),
      (_) => _loadBuses(showSpinner: false),
    );
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadBuses({bool showSpinner = true}) async {
    if (showSpinner && mounted) {
      setState(() {
        _loading = true;
        _errorMessage = null;
      });
    }

    try {
      final busRows = await supabase
          .from('buses')
          .select('id, bus_number, bus_code, driver_name, driver_phone, '
              'capacity, diesel_tank_capacity, mileage_kmpl')
          .eq('school_id', widget.schoolId)
          .order('bus_number');

      final enriched = <Map<String, dynamic>>[];

      for (final bus in busRows) {
        final busId = bus['id'];
        try {
          // Live speed + last update time
          final loc = await supabase
              .from('live_location')
              .select('speed, timestamp')
              .eq('bus_id', busId)
              .maybeSingle();

          double? speed;
          DateTime? lastUpdate;
          bool isLive = false;
          if (loc != null) {
            speed = (loc['speed'] as num?)?.toDouble();
            if (loc['timestamp'] != null) {
              lastUpdate = DateTime.parse(loc['timestamp']).toUtc();
              final secondsAgo =
                  DateTime.now().toUtc().difference(lastUpdate).inSeconds;
              isLive = secondsAgo < 60;
            }
          }

          // Total children assigned to this bus
          final students =
              await supabase.from('students').select('id').eq('bus_id', busId);
          final childrenCount = students.length;

          // Total stops on this bus's route
          int stopsCount = 0;
          final route = await supabase
              .from('routes')
              .select('id')
              .eq('bus_id', busId)
              .maybeSingle();
          if (route != null) {
            final stops = await supabase
                .from('stops')
                .select('id')
                .eq('route_id', route['id']);
            stopsCount = stops.length;
          }

          enriched.add({
            ...bus,
            'speed': speed,
            'is_live': isLive,
            'last_update': lastUpdate,
            'children_count': childrenCount,
            'stops_count': stopsCount,
            'is_overspeeding':
                isLive && speed != null && speed > kOverspeedThresholdKmh,
          });
        } catch (_) {
          // A missing optional table/policy must not hide the buses themselves.
          enriched.add({
            ...bus,
            'speed': null,
            'is_live': false,
            'last_update': null,
            'children_count': 0,
            'stops_count': 0,
            'is_overspeeding': false,
          });
        }
      }

      if (!mounted) return;
      setState(() {
        _buses = enriched;
        _loading = false;
        _errorMessage = null;
      });
    } on PostgrestException catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _errorMessage = error.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _errorMessage =
            'Could not load the dashboard. Check your connection and try again.';
      });
    }
  }

  int get _overspeedingCount =>
      _buses.where((b) => b['is_overspeeding'] == true).length;
  int get _liveCount =>
      _buses.where((b) => b['is_live'] == true).length;
  int get _offlineCount =>
      _buses.where((b) => b['is_live'] != true).length;

  Widget _buildStatusSummaryHeader() {
    return Container(
      padding: const EdgeInsets.all(12),
      color: Colors.white,
      child: Row(
        children: [
          _buildSummaryChip('Fleet Total', '${_buses.length}', Icons.directions_bus_rounded, const Color(0xFF0052CC)),
          const SizedBox(width: 8),
          _buildSummaryChip('Live Active', '$_liveCount', Icons.sensors_rounded, const Color(0xFF10B981)),
          const SizedBox(width: 8),
          _buildSummaryChip('Overspeed', '$_overspeedingCount', Icons.speed_rounded, const Color(0xFFEF4444)),
          const SizedBox(width: 8),
          _buildSummaryChip('Offline', '$_offlineCount', Icons.signal_wifi_off_rounded, const Color(0xFF64748B)),
        ],
      ),
    );
  }

  Widget _buildSummaryChip(String label, String value, IconData icon, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
        decoration: BoxDecoration(
          color: color.withOpacity(0.08),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withOpacity(0.2)),
        ),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 12, color: color),
                const SizedBox(width: 4),
                Text(value, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: color)),
              ],
            ),
            const SizedBox(height: 2),
            Text(label, style: TextStyle(fontSize: 10, color: Colors.grey.shade700), textAlign: TextAlign.center, overflow: TextOverflow.ellipsis),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F9FC),
      drawer: AdminDrawer(
        schoolId: widget.schoolId,
        schoolName: widget.schoolName,
        currentRoute: 'dashboard',
      ),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0052CC),
        foregroundColor: Colors.white,
        elevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Admin Dashboard',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
            Text(widget.schoolName,
                style: const TextStyle(fontSize: 12, color: Colors.white70)),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Route Optimizer',
            icon: const Icon(Icons.auto_awesome),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => RouteOptimizerScreen(
                schoolId: widget.schoolId,
                schoolName: widget.schoolName,
              ),
            )),
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => _loadBuses(),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF0052CC)))
          : _errorMessage != null
              ? _buildErrorState()
              : _buses.isEmpty
                  ? const Center(
                      child: Text('No buses registered for this school yet',
                          style: TextStyle(color: Colors.grey)),
                    )
                  : Column(
                      children: [
                        _buildStatusSummaryHeader(),
                        if (_overspeedingCount > 0) _buildOverspeedBanner(),
                        Expanded(
                          child: ListView.builder(
                            padding: const EdgeInsets.all(12),
                            itemCount: _buses.length,
                            itemBuilder: (context, index) =>
                                _buildBusListItem(_buses[index]),
                          ),
                        ),
                      ],
                    ),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 48, color: Colors.red),
            const SizedBox(height: 12),
            const Text('Dashboard unavailable',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text(_errorMessage!, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _loadBuses,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOverspeedBanner() {
    return Container(
      width: double.infinity,
      color: Colors.red.shade50,
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
      child: Row(
        children: [
          const Icon(Icons.warning_amber_rounded, color: Colors.red),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '$_overspeedingCount bus${_overspeedingCount > 1 ? 'es' : ''} '
              'exceeding ${kOverspeedThresholdKmh.toInt()} km/h right now',
              style: const TextStyle(
                color: Colors.red,
                fontWeight: FontWeight.bold,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBusListItem(Map<String, dynamic> bus) {
    final isLive = bus['is_live'] == true;
    final isOverspeeding = bus['is_overspeeding'] == true;
    final speed = bus['speed'] as double?;
    final capacity = bus['capacity'] ?? 0;
    final childrenCount = bus['children_count'] ?? 0;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: isOverspeeding ? Border.all(color: Colors.red, width: 2) : null,
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: CircleAvatar(
          backgroundColor: isOverspeeding
              ? Colors.red.shade50
              : isLive
                  ? Colors.green.shade50
                  : Colors.grey.shade100,
          child: Icon(
            Icons.directions_bus,
            color: isOverspeeding
                ? Colors.red
                : isLive
                    ? Colors.green
                    : Colors.grey,
          ),
        ),
        title: Text(
          bus['bus_number'] ?? 'Unnamed bus',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Text(
          '${bus['driver_name'] ?? 'Driver not assigned'}\n'
          '$childrenCount / $capacity children  |  ${bus['stops_count'] ?? 0} stops',
        ),
        isThreeLine: true,
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _LiveDot(isLive: isLive),
            const SizedBox(height: 4),
            Text(
              isLive ? '${speed?.toStringAsFixed(0) ?? '--'} km/h' : 'Offline',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: isLive ? Colors.green : Colors.grey,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LiveDot extends StatelessWidget {
  final bool isLive;
  const _LiveDot({required this.isLive});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(
        color: isLive ? Colors.green : Colors.grey.shade400,
        shape: BoxShape.circle,
      ),
    );
  }
}
