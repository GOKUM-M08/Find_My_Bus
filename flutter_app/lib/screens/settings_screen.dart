import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:http/http.dart' as http;
import 'config.dart';
import '../widgets/admin_drawer.dart';

const Color kPrimaryBlue = Color(0xFF0052CC);

class SettingsScreen extends StatefulWidget {
  final String schoolId;
  final String schoolName;

  const SettingsScreen({
    super.key,
    required this.schoolId,
    required this.schoolName,
  });

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final supabase = Supabase.instance.client;
  bool _loading = true;
  bool _dbConnected = false;
  bool _apiConnected = false;

  List<Map<String, dynamic>> _auditLogs = [];
  List<Map<String, dynamic>> _buses = [];
  Map<String, String> _tripDirections = {};

  @override
  void initState() {
    super.initState();
    _loadSettingsData();
  }

  Future<void> _loadSettingsData() async {
    setState(() => _loading = true);

    bool dbStatus = false;
    bool apiStatus = false;

    // Check Supabase
    try {
      await supabase.from('schools').select('id').limit(1);
      dbStatus = true;
    } catch (_) {
      dbStatus = false;
    }

    // Check Backend API
    try {
      final res = await http.get(Uri.parse(kBackendBaseUrl)).timeout(const Duration(seconds: 5));
      if (res.statusCode == 200) {
        apiStatus = true;
      }
    } catch (_) {
      apiStatus = false;
    }

    // Fetch Audit Logs
    List<Map<String, dynamic>> logs = [];
    try {
      final logRows = await supabase
          .from('admin_audit_logs')
          .select('*')
          .eq('school_id', widget.schoolId)
          .order('created_at', ascending: false)
          .limit(50);
      logs = List<Map<String, dynamic>>.from(logRows);
    } catch (_) {}

    // Fetch Buses & Trip Directions
    List<Map<String, dynamic>> buses = [];
    final directions = <String, String>{};
    try {
      final busRows = await supabase
          .from('buses')
          .select('id, bus_number, driver_name')
          .eq('school_id', widget.schoolId);
      buses = List<Map<String, dynamic>>.from(busRows);

      for (final b in buses) {
        final bId = b['id'] as String;
        try {
          final res = await http.get(Uri.parse('$kBackendBaseUrl/api/tracking/$bId/trip-direction')).timeout(const Duration(seconds: 3));
          if (res.statusCode == 200) {
            final data = jsonDecode(res.body);
            directions[bId] = data['trip_direction'] ?? 'morning';
          }
        } catch (_) {
          directions[bId] = 'morning';
        }
      }
    } catch (_) {}

    if (!mounted) return;
    setState(() {
      _dbConnected = dbStatus;
      _apiConnected = apiStatus;
      _auditLogs = logs;
      _buses = buses;
      _tripDirections = directions;
      _loading = false;
    });
  }

  Future<void> _overrideTripDirection(String busId, String newDirection) async {
    try {
      final res = await http.post(
        Uri.parse('$kBackendBaseUrl/api/tracking/$busId/trip-direction'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'trip_direction': newDirection}),
      );

      if (res.statusCode == 200) {
        setState(() {
          _tripDirections[busId] = newDirection;
        });

        // Audit log
        final user = supabase.auth.currentUser;
        await supabase.from('admin_audit_logs').insert({
          'school_id': widget.schoolId,
          'admin_user_id': user?.id,
          'admin_email': user?.email,
          'action_type': 'TRIP_DIRECTION_OVERRIDE',
          'target_entity': 'buses',
          'target_id': busId,
          'details': 'Manually overridden trip direction to $newDirection',
        });

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Trip direction manually set to "$newDirection"')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to override direction: ${e.toString()}'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = MediaQuery.of(context).size.width >= 800;

    return Scaffold(
      backgroundColor: const Color(0xFFF7F9FC),
      drawer: AdminDrawer(
        schoolId: widget.schoolId,
        schoolName: widget.schoolName,
        currentRoute: 'settings',
      ),
      appBar: AppBar(
        title: Text('${widget.schoolName} — Settings & Audit Logs'),
        backgroundColor: kPrimaryBlue,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadSettingsData,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: kPrimaryBlue))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildHealthStatusCard(),
                  const SizedBox(height: 20),
                  _buildTripDirectionOverrideSection(),
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Admin Action Audit Log', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                      Text('${_auditLogs.length} Recent Log Entries', style: const TextStyle(color: Colors.grey)),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _auditLogs.isEmpty
                      ? const Center(child: Padding(padding: EdgeInsets.all(32), child: Text('No admin audit logs recorded yet.')))
                      : isDesktop
                          ? _buildDesktopAuditTable()
                          : _buildMobileAuditList(),
                ],
              ),
            ),
    );
  }

  Widget _buildHealthStatusCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('System Health & Connectivity Status', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 12),
          Row(
            children: [
              Icon(_dbConnected ? Icons.check_circle : Icons.error, color: _dbConnected ? Colors.green : Colors.red),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _dbConnected ? 'Supabase Database Connected' : 'Supabase Connection Error',
                  style: TextStyle(fontWeight: FontWeight.bold, color: _dbConnected ? Colors.green : Colors.red),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(_apiConnected ? Icons.check_circle : Icons.warning_amber_rounded, color: _apiConnected ? Colors.green : Colors.orange),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _apiConnected ? 'Python FastAPI Backend Connected ($kBackendBaseUrl)' : 'FastAPI Backend Offline / Unreachable ($kBackendBaseUrl)',
                  style: TextStyle(fontWeight: FontWeight.bold, color: _apiConnected ? Colors.green : Colors.orange),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text('Active School Scope ID: ${widget.schoolId}', style: const TextStyle(fontSize: 12, color: Colors.grey)),
        ],
      ),
    );
  }

  Widget _buildTripDirectionOverrideSection() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Manual Trip Direction Override', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 4),
          const Text(
            'Override automated trip direction calculation for edge cases (e.g. correcting after false auto-flip).',
            style: TextStyle(fontSize: 12, color: Colors.grey),
          ),
          const SizedBox(height: 12),
          _buses.isEmpty
              ? const Text('No buses available.')
              : Column(
                  children: _buses.map((bus) {
                    final bId = bus['id'] as String;
                    final currentDir = _tripDirections[bId] ?? 'morning';

                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              '${bus['bus_number']} (${bus['driver_name'] ?? 'Driver'})',
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                            ),
                          ),
                          SegmentedButton<String>(
                            segments: const [
                              ButtonSegment(value: 'morning', label: Text('Morning Pickup')),
                              ButtonSegment(value: 'evening', label: Text('Evening Dropoff')),
                            ],
                            selected: {currentDir},
                            onSelectionChanged: (setVal) {
                              if (setVal.isNotEmpty) {
                                _overrideTripDirection(bId, setVal.first);
                              }
                            },
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ),
        ],
      ),
    );
  }

  Widget _buildDesktopAuditTable() {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: DataTable(
        columns: const [
          DataColumn(label: Text('Timestamp')),
          DataColumn(label: Text('Admin User')),
          DataColumn(label: Text('Action Type')),
          DataColumn(label: Text('Target Entity')),
          DataColumn(label: Text('Details')),
        ],
        rows: _auditLogs.map((log) {
          final ts = log['created_at'] != null ? DateTime.parse(log['created_at']).toLocal().toString().split('.')[0] : '—';
          return DataRow(cells: [
            DataCell(Text(ts, style: const TextStyle(fontSize: 12))),
            DataCell(Text(log['admin_email'] ?? 'Admin', style: const TextStyle(fontSize: 13))),
            DataCell(Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(color: kPrimaryBlue.withOpacity(0.1), borderRadius: BorderRadius.circular(4)),
              child: Text(log['action_type'] ?? '', style: const TextStyle(color: kPrimaryBlue, fontWeight: FontWeight.bold, fontSize: 11)),
            )),
            DataCell(Text(log['target_entity'] ?? '—')),
            DataCell(Text(log['details'] ?? '—')),
          ]);
        }).toList(),
      ),
    );
  }

  Widget _buildMobileAuditList() {
    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: _auditLogs.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, idx) {
        final log = _auditLogs[idx];
        final ts = log['created_at'] != null ? DateTime.parse(log['created_at']).toLocal().toString().split('.')[0] : '—';
        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.grey.shade300),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(log['action_type'] ?? '', style: const TextStyle(fontWeight: FontWeight.bold, color: kPrimaryBlue)),
                  Text(ts, style: const TextStyle(fontSize: 11, color: Colors.grey)),
                ],
              ),
              const SizedBox(height: 2),
              Text('By: ${log['admin_email'] ?? 'Admin'}'),
              Text('Details: ${log['details'] ?? '—'}'),
            ],
          ),
        );
      },
    );
  }
}
