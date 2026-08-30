import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
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
            const Text('Admin Dashboard',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
            Text(widget.schoolName,
                style: const TextStyle(fontSize: 13, color: Colors.white70)),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Route Optimizer',
            icon: const Icon(Icons.route_outlined),
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
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage != null
              ? _buildErrorState()
              : _buses.isEmpty
                  ? const Center(
                      child: Text('No buses registered for this school yet',
                          style: TextStyle(color: Colors.grey)),
                    )
                  : Column(
                      children: [
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

  Widget _buildBusCard(Map<String, dynamic> bus) {
    final isOverspeeding = bus['is_overspeeding'] == true;
    final isLive = bus['is_live'] == true;
    final speed = bus['speed'] as double?;
    final capacity = bus['capacity'] ?? 0;
    final childrenCount = bus['children_count'] ?? 0;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: isOverspeeding ? Border.all(color: Colors.red, width: 2) : null,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              width: 5,
              decoration: BoxDecoration(
                color: isOverspeeding
                    ? Colors.red
                    : (isLive ? Colors.green : Colors.grey.shade400),
                borderRadius: const BorderRadius.horizontal(
                  left: Radius.circular(12),
                ),
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (isOverspeeding)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                          vertical: 6, horizontal: 12),
                      decoration: const BoxDecoration(
                        color: Colors.red,
                        borderRadius:
                            BorderRadius.vertical(top: Radius.circular(10)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.warning_amber_rounded,
                              color: Colors.white, size: 16),
                          const SizedBox(width: 6),
                          Text(
                            'OVERSPEEDING — ${speed!.toStringAsFixed(0)} km/h',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                bus['bus_number'] ?? '',
                                style: const TextStyle(
                                    fontSize: 17, fontWeight: FontWeight.bold),
                              ),
                            ),
                            _LiveDot(isLive: isLive),
                            const SizedBox(width: 6),
                            Text(
                              isLive
                                  ? '${speed?.toStringAsFixed(0) ?? '--'} km/h'
                                  : 'Offline',
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                color: isLive ? Colors.green : Colors.grey,
                              ),
                            ),
                          ],
                        ),
                        if (bus['driver_name'] != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Row(
                              children: [
                                Text(
                                  'Driver: ${bus['driver_name']}',
                                  style: const TextStyle(
                                      color: Colors.grey, fontSize: 13),
                                ),
                                if (bus['driver_phone'] != null) ...[
                                  const SizedBox(width: 8),
                                  TextButton.icon(
                                    onPressed: () => launchUrl(Uri.parse(
                                        'tel:${bus['driver_phone']}')),
                                    icon: const Icon(Icons.call_outlined,
                                        size: 17),
                                    label: Text('Call ${bus['driver_name']}'),
                                    style: TextButton.styleFrom(
                                      foregroundColor: const Color(0xFF1E6BFF),
                                      minimumSize: const Size(40, 40),
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 10),
                                      tapTargetSize:
                                          MaterialTapTargetSize.shrinkWrap,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        const Divider(height: 20),
                        GridView.count(
                          crossAxisCount: 2,
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          childAspectRatio: 2.6,
                          mainAxisSpacing: 4,
                          children: [
                            _StatItem(
                              icon: Icons.groups_outlined,
                              label: 'Children',
                              value: '$childrenCount / $capacity',
                            ),
                            _StatItem(
                              icon: Icons.place_outlined,
                              label: 'Stops',
                              value: '${bus['stops_count']}',
                            ),
                            _StatItem(
                              icon: Icons.local_gas_station_outlined,
                              label: 'Tank Capacity',
                              value: bus['diesel_tank_capacity'] != null
                                  ? '${bus['diesel_tank_capacity']} L'
                                  : 'Not set',
                            ),
                            _StatItem(
                              icon: Icons.speed_outlined,
                              label: 'Mileage',
                              value: bus['mileage_kmpl'] != null
                                  ? '${bus['mileage_kmpl']} km/L'
                                  : 'Not set',
                            ),
                          ],
                        ),
                        // Extra feature: occupancy indicator
                        if (capacity > 0) ...[
                          const SizedBox(height: 8),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(6),
                            child: LinearProgressIndicator(
                              value: (childrenCount / capacity).clamp(0, 1),
                              minHeight: 6,
                              backgroundColor: Colors.grey.shade200,
                              color: childrenCount >= capacity
                                  ? Colors.red
                                  : const Color(0xFF1E6BFF),
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${((childrenCount / capacity) * 100).clamp(0, 100).toStringAsFixed(0)}% occupied',
                            style: const TextStyle(
                                fontSize: 11, color: Colors.grey),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
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

class _StatItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _StatItem({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(right: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF1E6BFF).withOpacity(0.06),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: const Color(0xFF1E6BFF)),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  value,
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 13),
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  label,
                  style: const TextStyle(fontSize: 10, color: Colors.grey),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
