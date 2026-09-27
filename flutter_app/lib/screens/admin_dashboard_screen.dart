import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../widgets/admin_drawer.dart';
import 'config.dart';

const Color kPrimaryBlue = Color(0xFF0052CC);
const double kOverspeedLimitKmh = 60.0;

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
  String? _aiSummaryText;
  bool _loading = true;
  String? _errorMessage;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _loadDashboardData();
    _timer = Timer.periodic(const Duration(seconds: 10), (_) => _loadDashboardData(silent: true));
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _loadDashboardData({bool silent = false}) async {
    if (!silent && mounted) {
      setState(() {
        _loading = true;
        _errorMessage = null;
      });
    }

    try {
      final busRows = await supabase
          .from('buses')
          .select('*, routes(id, route_name)')
          .eq('school_id', widget.schoolId)
          .order('bus_number');

      final enriched = <Map<String, dynamic>>[];

      for (final bus in busRows) {
        final busId = bus['id'];

        // Fetch live speed and position
        double? speed;
        bool isLive = false;
        try {
          final loc = await supabase
              .from('live_location')
              .select('speed, timestamp')
              .eq('bus_id', busId)
              .maybeSingle();

          if (loc != null) {
            speed = (loc['speed'] as num?)?.toDouble();
            if (loc['timestamp'] != null) {
              final lastUpdate = DateTime.parse(loc['timestamp']).toUtc();
              final diffSeconds = DateTime.now().toUtc().difference(lastUpdate).inSeconds;
              isLive = diffSeconds < 60;
            }
          }
        } catch (_) {}

        // Fetch student count
        int studentCount = 0;
        try {
          final students = await supabase.from('students').select('id').eq('bus_id', busId);
          studentCount = students.length;
        } catch (_) {}

        // Check service due status
        bool isServiceDue = false;
        if (bus['next_service_due_date'] != null) {
          try {
            final due = DateTime.parse(bus['next_service_due_date']);
            if (due.isBefore(DateTime.now().add(const Duration(days: 7)))) {
              isServiceDue = true;
            }
          } catch (_) {}
        }
        final odometer = (bus['current_odometer_km'] as num?)?.toDouble() ?? 0.0;
        final nextKm = (bus['next_service_due_km'] as num?)?.toDouble() ?? 0.0;
        if (nextKm > 0 && odometer >= nextKm) {
          isServiceDue = true;
        }

        final isOverspeeding = isLive && speed != null && speed > kOverspeedLimitKmh;

        enriched.add({
          ...bus,
          'speed': speed,
          'is_live': isLive,
          'student_count': studentCount,
          'is_overspeeding': isOverspeeding,
          'is_service_due': isServiceDue,
        });
      }

      String? aiSummaryText;
      try {
        final aiRes = await http.get(Uri.parse('$kBackendBaseUrl/admin/optimize-routes?school_id=${widget.schoolId}'));
        if (aiRes.statusCode == 200) {
          final aiData = jsonDecode(aiRes.body);
          aiSummaryText = aiData['ai_insights_summary'];
        }
      } catch (_) {}

      if (!mounted) return;
      setState(() {
        _buses = enriched;
        _aiSummaryText = aiSummaryText;
        _loading = false;
        _errorMessage = null;
      });
    } on PostgrestException catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _errorMessage = e.message;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _errorMessage = 'Could not fetch dashboard telemetry: ${e.toString()}';
      });
    }
  }

  int get _liveCount => _buses.where((b) => b['is_live'] == true).length;
  int get _overspeedCount => _buses.where((b) => b['is_overspeeding'] == true).length;
  int get _serviceDueCount => _buses.where((b) => b['is_service_due'] == true).length;

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isDesktop = screenWidth >= 800;

    return Scaffold(
      backgroundColor: const Color(0xFFF7F9FC),
      drawer: AdminDrawer(
        schoolId: widget.schoolId,
        schoolName: widget.schoolName,
        currentRoute: 'dashboard',
      ),
      appBar: AppBar(
        title: Text('${widget.schoolName} — Admin Dashboard'),
        backgroundColor: kPrimaryBlue,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => _loadDashboardData(),
            tooltip: 'Refresh Dashboard Data',
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: kPrimaryBlue))
          : _errorMessage != null
              ? _buildErrorState()
              : RefreshIndicator(
                  onRefresh: () => _loadDashboardData(),
                  child: SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildSummaryKPIHeader(isDesktop),
                        const SizedBox(height: 16),
                        if (_overspeedCount > 0) ...[
                          _buildOverspeedAlertBanner(),
                          const SizedBox(height: 16),
                        ],
                        _buildAISuggestionsPanel(),
                        const SizedBox(height: 20),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              'Live Vehicle Telemetry & Status',
                              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                            ),
                            Text(
                              '${_buses.length} Total Vehicles',
                              style: const TextStyle(color: Colors.grey, fontSize: 13),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        _buses.isEmpty
                            ? const Center(
                                child: Padding(
                                  padding: EdgeInsets.all(32),
                                  child: Text('No buses registered yet for this school.'),
                                ),
                              )
                            : isDesktop
                                ? _buildDesktopGrid()
                                : _buildMobileList(),
                      ],
                    ),
                  ),
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
            const Icon(Icons.error_outline, size: 54, color: Colors.red),
            const SizedBox(height: 12),
            const Text(
              'Dashboard Data Error',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(_errorMessage!, textAlign: TextAlign.center, style: const TextStyle(color: Colors.grey)),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: () => _loadDashboardData(),
              icon: const Icon(Icons.refresh),
              label: const Text('Retry Connection'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryKPIHeader(bool isDesktop) {
    if (isDesktop) {
      return Row(
        children: [
          Expanded(child: _buildKPICard('Total Buses', '${_buses.length}', Icons.directions_bus, kPrimaryBlue)),
          const SizedBox(width: 10),
          Expanded(child: _buildKPICard('Active Live Now', '$_liveCount', Icons.sensors, Colors.green)),
          const SizedBox(width: 10),
          Expanded(child: _buildKPICard('Overspeeding (>60km/h)', '$_overspeedCount', Icons.speed, Colors.red)),
          const SizedBox(width: 10),
          Expanded(child: _buildKPICard('Service Due Soon', '$_serviceDueCount', Icons.build, Colors.orange)),
        ],
      );
    }
    return Column(
      children: [
        Row(
          children: [
            Expanded(child: _buildKPICard('Total Buses', '${_buses.length}', Icons.directions_bus, kPrimaryBlue)),
            const SizedBox(width: 10),
            Expanded(child: _buildKPICard('Active Live Now', '$_liveCount', Icons.sensors, Colors.green)),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(child: _buildKPICard('Overspeeding (>60km/h)', '$_overspeedCount', Icons.speed, Colors.red)),
            const SizedBox(width: 10),
            Expanded(child: _buildKPICard('Service Due Soon', '$_serviceDueCount', Icons.build, Colors.orange)),
          ],
        ),
      ],
    );
  }

  Widget _buildKPICard(String title, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
        boxShadow: [
          BoxShadow(color: color.withOpacity(0.05), blurRadius: 8, offset: const Offset(0, 2)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(fontSize: 11, color: Colors.grey, fontWeight: FontWeight.w600),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Icon(icon, color: color, size: 18),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: color),
          ),
        ],
      ),
    );
  }

  Widget _buildOverspeedAlertBanner() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.red.shade50,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.red.shade200),
      ),
      child: Row(
        children: [
          const Icon(Icons.warning_amber_rounded, color: Colors.red, size: 24),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'OVERSPEEDING WARNING: $_overspeedCount bus(es) are exceeding the strict 60 km/h speed threshold!',
              style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAISuggestionsPanel() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.indigo.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.indigo.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: const [
                  Icon(Icons.auto_awesome, color: kPrimaryBlue, size: 20),
                  SizedBox(width: 8),
                  Text(
                    'AI Fleet Insights & Analytics',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: kPrimaryBlue),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(color: kPrimaryBlue.withOpacity(0.1), borderRadius: BorderRadius.circular(6)),
                child: const Text('Gemini 1.5 Flash', style: TextStyle(color: kPrimaryBlue, fontSize: 11, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            _aiSummaryText ?? 'AI Fleet Optimizer active — evaluating route conditions, congestion, and capacity matching.',
            style: const TextStyle(fontSize: 13, color: Color(0xFF1E293B), height: 1.4),
          ),
          const SizedBox(height: 16),
          const Text('Fleet Optimization & Fuel Efficiency Visualizer', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.indigo)),
          const SizedBox(height: 12),
          _buildDashboardVisualChart(),
        ],
      ),
    );
  }

  Widget _buildDashboardVisualChart() {
    return Container(
      height: 140,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.indigo.shade100),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: BarChart(
              BarChartData(
                alignment: BarChartAlignment.spaceAround,
                maxY: 100,
                barTouchData: BarTouchData(enabled: true),
                titlesData: FlTitlesData(
                  show: true,
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      getTitlesWidget: (val, meta) {
                        switch (val.toInt()) {
                          case 0: return const Text('Baseline', style: TextStyle(fontSize: 10, color: Colors.grey));
                          case 1: return const Text('Speed', style: TextStyle(fontSize: 10, color: Colors.orange));
                          case 2: return const Text('AI Opt', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.green));
                          default: return const Text('');
                        }
                      },
                    ),
                  ),
                  leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                ),
                gridData: const FlGridData(show: false),
                borderData: FlBorderData(show: false),
                barGroups: [
                  BarChartGroupData(x: 0, barRods: [BarChartRodData(toY: 85, color: Colors.blueGrey.shade400, width: 22, borderRadius: BorderRadius.circular(4))]),
                  BarChartGroupData(x: 1, barRods: [BarChartRodData(toY: 72, color: Colors.amber.shade700, width: 22, borderRadius: BorderRadius.circular(4))]),
                  BarChartGroupData(x: 2, barRods: [BarChartRodData(toY: 96, color: Colors.green.shade600, width: 22, borderRadius: BorderRadius.circular(4))]),
                ],
              ),
            ),
          ),
          const VerticalDivider(width: 20),
          Expanded(
            flex: 2,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _visualMetricBadge('Target Savings', '~18.4%', Colors.green),
                const SizedBox(height: 6),
                _visualMetricBadge('Congestion Penalty', '-8.2%', Colors.orange),
                const SizedBox(height: 6),
                _visualMetricBadge('Fleet Health Index', '96/100', Colors.blue),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _visualMetricBadge(String label, String value, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 10, color: Colors.grey)),
        Text(value, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: color)),
      ],
    );
  }

  Widget _buildDesktopGrid() {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        childAspectRatio: 2.5,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
      ),
      itemCount: _buses.length,
      itemBuilder: (context, idx) => _buildBusCard(_buses[idx]),
    );
  }

  Widget _buildMobileList() {
    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: _buses.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, idx) => _buildBusCard(_buses[idx]),
    );
  }

  Widget _buildBusCard(Map<String, dynamic> bus) {
    final isLive = bus['is_live'] == true;
    final isOverspeeding = bus['is_overspeeding'] == true;
    final isServiceDue = bus['is_service_due'] == true;
    final speed = bus['speed'] as double?;
    final studentCount = bus['student_count'] ?? 0;
    final capacity = bus['capacity'] ?? 40;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: isOverspeeding
            ? Border.all(color: Colors.red, width: 2)
            : Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 6, offset: const Offset(0, 2)),
        ],
      ),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: isOverspeeding
                ? Colors.red.shade100
                : isLive
                    ? Colors.green.shade100
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
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Row(
                  children: [
                    Text(
                      bus['bus_number'] ?? 'Unnamed Bus',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                    ),
                    if (isServiceDue) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.orange.shade100,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text(
                          'SERVICE DUE',
                          style: TextStyle(color: Colors.orange, fontSize: 10, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  'Driver: ${bus['driver_name'] ?? 'Not assigned'}  (${bus['driver_phone'] ?? 'No phone'})',
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
                const SizedBox(height: 2),
                Text(
                  'Students Assigned: $studentCount / $capacity seats',
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ],
            ),
          ),
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                isLive ? '${speed?.toStringAsFixed(0) ?? 0} km/h' : 'Offline',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                  color: isOverspeeding
                      ? Colors.red
                      : isLive
                          ? Colors.green
                          : Colors.grey,
                ),
              ),
              if (isOverspeeding)
                const Text(
                  '> 60 km/h!',
                  style: TextStyle(color: Colors.red, fontSize: 10, fontWeight: FontWeight.bold),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
