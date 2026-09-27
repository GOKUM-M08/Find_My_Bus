import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../widgets/admin_drawer.dart';

const Color kPrimaryBlue = Color(0xFF0052CC);

class BusProfileScreen extends StatefulWidget {
  final String schoolId;
  final String schoolName;

  const BusProfileScreen({
    super.key,
    required this.schoolId,
    required this.schoolName,
  });

  @override
  State<BusProfileScreen> createState() => _BusProfileScreenState();
}

class _BusProfileScreenState extends State<BusProfileScreen> {
  final supabase = Supabase.instance.client;
  List<Map<String, dynamic>> _buses = [];
  bool _loading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _fetchBuses();
  }

  Future<void> _fetchBuses() async {
    setState(() {
      _loading = true;
      _errorMessage = null;
    });

    try {
      final busData = await supabase
          .from('buses')
          .select('*')
          .eq('school_id', widget.schoolId)
          .order('bus_number');

      final locData = await supabase.from('live_location').select('*');
      final locList = List<Map<String, dynamic>>.from(locData);

      final routeData = await supabase.from('routes').select('*').eq('school_id', widget.schoolId);
      final routeList = List<Map<String, dynamic>>.from(routeData);

      final merged = (busData as List).map<Map<String, dynamic>>((b) {
        Map<String, dynamic>? loc;
        for (final l in locList) {
          if (l['bus_id'] == b['id']) {
            loc = l;
            break;
          }
        }
        Map<String, dynamic>? assignedRoute;
        for (final r in routeList) {
          if (r['bus_id'] == b['id']) {
            assignedRoute = r;
            break;
          }
        }
        return {
          ...Map<String, dynamic>.from(b),
          'location': loc,
          'assigned_route': assignedRoute,
        };
      }).toList();

      if (!mounted) return;
      setState(() {
        _buses = merged;
        _loading = false;
      });
    } on PostgrestException catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = e.message;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Could not load bus fleet: ${e.toString()}';
        _loading = false;
      });
    }
  }

  Future<void> _logAudit(String actionType, String targetId, String details) async {
    try {
      final user = supabase.auth.currentUser;
      await supabase.from('admin_audit_logs').insert({
        'school_id': widget.schoolId,
        'admin_user_id': user?.id,
        'admin_email': user?.email,
        'action_type': actionType,
        'target_entity': 'buses',
        'target_id': targetId,
        'details': details,
      });
    } catch (_) {}
  }

  void _showAddEditBusModal([Map<String, dynamic>? existingBus]) {
    final formKey = GlobalKey<FormState>();
    final isEdit = existingBus != null;

    final busNumberCtrl = TextEditingController(text: existingBus?['bus_number'] ?? '');
    final busCodeCtrl = TextEditingController(text: existingBus?['bus_code'] ?? '');
    final driverNameCtrl = TextEditingController(text: existingBus?['driver_name'] ?? '');
    final driverPhoneCtrl = TextEditingController(text: existingBus?['driver_phone'] ?? '');
    final deviceIdCtrl = TextEditingController(text: existingBus?['device_id'] ?? '');
    final capacityCtrl = TextEditingController(text: (existingBus?['capacity'] ?? 40).toString());
    final odometerCtrl = TextEditingController(text: (existingBus?['current_odometer_km'] ?? 0).toString());
    final serviceDueKmCtrl = TextEditingController(text: (existingBus?['next_service_due_km'] ?? 0).toString());

    DateTime? lastServiceDate = existingBus?['last_service_date'] != null
        ? DateTime.tryParse(existingBus!['last_service_date'])
        : null;

    bool saving = false;
    String? modalError;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) {
          return AlertDialog(
            title: Text(isEdit ? 'Edit Vehicle Details' : 'Register New Vehicle'),
            content: SingleChildScrollView(
              child: Container(
                width: 450,
                child: Form(
                  key: formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (modalError != null) ...[
                        Container(
                          padding: const EdgeInsets.all(10),
                          color: Colors.red.shade50,
                          child: Text(modalError!, style: const TextStyle(color: Colors.red, fontSize: 13)),
                        ),
                        const SizedBox(height: 12),
                      ],
                      TextFormField(
                        controller: busNumberCtrl,
                        decoration: const InputDecoration(labelText: 'Bus Registration Number * (e.g. TN09 AB 1234)'),
                        validator: (v) => (v == null || v.trim().isEmpty) ? 'Registration number is required' : null,
                      ),
                      const SizedBox(height: 10),
                      TextFormField(
                        controller: busCodeCtrl,
                        decoration: const InputDecoration(labelText: 'Bus Designation / Code (e.g. Bus-A)'),
                      ),
                      const SizedBox(height: 10),
                      TextFormField(
                        controller: driverNameCtrl,
                        decoration: const InputDecoration(labelText: 'Assigned Driver Name'),
                      ),
                      const SizedBox(height: 10),
                      TextFormField(
                        controller: driverPhoneCtrl,
                        keyboardType: TextInputType.phone,
                        decoration: const InputDecoration(labelText: 'Driver Phone Number'),
                      ),
                      const SizedBox(height: 10),
                      TextFormField(
                        controller: deviceIdCtrl,
                        decoration: const InputDecoration(labelText: 'GPS Tracker Device ID / Serial *'),
                        validator: (v) => (v == null || v.trim().isEmpty) ? 'GPS Device ID is required' : null,
                      ),
                      const SizedBox(height: 10),
                      TextFormField(
                        controller: capacityCtrl,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: 'Seating Capacity (Students) *'),
                        validator: (v) {
                          final numVal = int.tryParse(v ?? '');
                          if (numVal == null || numVal <= 0) return 'Enter a valid positive seating capacity';
                          return null;
                        },
                      ),
                      const SizedBox(height: 10),
                      TextFormField(
                        controller: odometerCtrl,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: 'Current Odometer (km)'),
                        validator: (v) {
                          if (v != null && v.isNotEmpty && (double.tryParse(v) ?? -1) < 0) {
                            return 'Odometer reading cannot be negative';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 10),
                      TextFormField(
                        controller: serviceDueKmCtrl,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: 'Next Service Due at Odometer (km)'),
                      ),
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              lastServiceDate != null
                                  ? 'Last Service: ${lastServiceDate.toString().split(' ')[0]}'
                                  : 'Last Service Date: Not set',
                              style: const TextStyle(fontSize: 13),
                            ),
                          ),
                          TextButton(
                            onPressed: () async {
                              final picked = await showDatePicker(
                                context: context,
                                initialDate: lastServiceDate ?? DateTime.now(),
                                firstDate: DateTime(2020),
                                lastDate: DateTime.now(),
                              );
                              if (picked != null) {
                                setModalState(() => lastServiceDate = picked);
                              }
                            },
                            child: const Text('Pick Date'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: saving ? null : () => Navigator.pop(ctx),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: kPrimaryBlue, foregroundColor: Colors.white),
                onPressed: saving
                    ? null
                    : () async {
                        if (!formKey.currentState!.validate()) return;
                        setModalState(() {
                          saving = true;
                          modalError = null;
                        });

                        final payload = {
                          'school_id': widget.schoolId,
                          'bus_number': busNumberCtrl.text.trim(),
                          'bus_code': busCodeCtrl.text.trim(),
                          'driver_name': driverNameCtrl.text.trim(),
                          'driver_phone': driverPhoneCtrl.text.trim(),
                          'device_id': deviceIdCtrl.text.trim(),
                          'capacity': int.parse(capacityCtrl.text.trim()),
                          'current_odometer_km': double.tryParse(odometerCtrl.text.trim()) ?? 0.0,
                          'next_service_due_km': double.tryParse(serviceDueKmCtrl.text.trim()) ?? 0.0,
                          'last_service_date': lastServiceDate?.toIso8601String().split('T')[0],
                        };

                        try {
                          if (isEdit) {
                            await supabase.from('buses').update(payload).eq('id', existingBus['id']);
                            await _logAudit('UPDATE_BUS', existingBus['id'], 'Updated bus ${busNumberCtrl.text.trim()}');
                          } else {
                            final res = await supabase.from('buses').insert(payload).select();
                            final newId = (res as List).isNotEmpty ? res[0]['id'] : '';
                            await _logAudit('CREATE_BUS', newId.toString(), 'Created bus ${busNumberCtrl.text.trim()}');
                          }

                          if (mounted) {
                            Navigator.pop(ctx);
                            _fetchBuses();
                          }
                        } catch (e) {
                          setModalState(() {
                            saving = false;
                            modalError = 'Failed to save vehicle: ${e.toString()}';
                          });
                        }
                      },
                child: saving
                    ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : Text(isEdit ? 'Save Changes' : 'Register Vehicle'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _deleteBus(Map<String, dynamic> bus) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirm Vehicle Deletion'),
        content: Text('Are you sure you want to delete bus "${bus['bus_number']}"? This destructive action cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete Vehicle'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await supabase.from('buses').delete().eq('id', bus['id']);
        await _logAudit('DELETE_BUS', bus['id'], 'Deleted bus ${bus['bus_number']}');
        _fetchBuses();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Bus "${bus['bus_number']}" deleted successfully.')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to delete bus: ${e.toString()}'), backgroundColor: Colors.red),
          );
        }
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
        currentRoute: 'buses',
      ),
      appBar: AppBar(
        title: Text('${widget.schoolName} — Bus Fleet Management'),
        backgroundColor: kPrimaryBlue,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: 'Register New Bus',
            onPressed: () => _showAddEditBusModal(),
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => _fetchBuses(),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: kPrimaryBlue))
          : _errorMessage != null
              ? _buildErrorState()
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Fleet Vehicle List', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                          ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(backgroundColor: kPrimaryBlue, foregroundColor: Colors.white),
                            onPressed: () => _showAddEditBusModal(),
                            icon: const Icon(Icons.directions_bus),
                            label: const Text('Register Vehicle'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      _buildLiveMapOverview(),
                      const SizedBox(height: 20),
                      _buses.isEmpty
                          ? const Center(child: Padding(padding: EdgeInsets.all(32), child: Text('No vehicles registered.')))
                          : isDesktop
                              ? _buildDesktopTable()
                              : _buildMobileCards(),
                    ],
                  ),
                ),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline, color: Colors.red, size: 48),
          const SizedBox(height: 12),
          Text(_errorMessage!),
          const SizedBox(height: 12),
          ElevatedButton(onPressed: _fetchBuses, child: const Text('Retry')),
        ],
      ),
    );
  }

  Widget _buildLiveMapOverview() {
    final markers = <Marker>[];
    for (final b in _buses) {
      if (b['location'] != null && b['location']['latitude'] != null && b['location']['longitude'] != null) {
        markers.add(
          Marker(
            point: LatLng(
              (b['location']['latitude'] as num).toDouble(),
              (b['location']['longitude'] as num).toDouble(),
            ),
            width: 40,
            height: 40,
            child: const Icon(Icons.directions_bus_filled, color: kPrimaryBlue, size: 32),
          ),
        );
      }
    }

    return Container(
      height: 220,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: FlutterMap(
          options: MapOptions(
            initialCenter: markers.isNotEmpty ? markers.first.point : const LatLng(13.0827, 80.2707),
            initialZoom: 12.0,
          ),
          children: [
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'com.bustrack.app',
            ),
            MarkerLayer(markers: markers),
          ],
        ),
      ),
    );
  }

  Widget _buildDesktopTable() {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: DataTable(
        columns: const [
          DataColumn(label: Text('Bus Number')),
          DataColumn(label: Text('Code')),
          DataColumn(label: Text('Driver')),
          DataColumn(label: Text('Assigned Route & Conditions')),
          DataColumn(label: Text('Capacity')),
          DataColumn(label: Text('Odometer')),
          DataColumn(label: Text('Actions')),
        ],
        rows: _buses.map((bus) {
          final route = bus['assigned_route'] as Map<String, dynamic>?;
          return DataRow(cells: [
            DataCell(Text(bus['bus_number'] ?? '', style: const TextStyle(fontWeight: FontWeight.bold))),
            DataCell(Text(bus['bus_code'] ?? '—')),
            DataCell(Text('${bus['driver_name'] ?? '—'}\n${bus['driver_phone'] ?? ''}')),
            DataCell(route == null
                ? const Text('Route: Unassigned', style: TextStyle(color: Colors.grey, fontStyle: FontStyle.italic, fontSize: 12))
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(route['route_name'] ?? 'Route', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: kPrimaryBlue)),
                      Text('Traffic: ${route['traffic_level'] ?? 'medium'} | Road: ${route['road_quality'] ?? 'average'}', style: const TextStyle(fontSize: 11)),
                      Text('Breakers: ${route['speed_breaker_count'] ?? 0} | Turns: ${route['sharp_turn_count'] ?? 0}', style: const TextStyle(fontSize: 11, color: Colors.grey)),
                    ],
                  )),
            DataCell(Text('${bus['capacity'] ?? 40} seats')),
            DataCell(Text('${bus['current_odometer_km'] ?? 0} km')),
            DataCell(Row(
              children: [
                IconButton(icon: const Icon(Icons.edit, color: kPrimaryBlue), onPressed: () => _showAddEditBusModal(bus)),
                IconButton(icon: const Icon(Icons.delete, color: Colors.red), onPressed: () => _deleteBus(bus)),
              ],
            )),
          ]);
        }).toList(),
      ),
    );
  }

  Widget _buildMobileCards() {
    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: _buses.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, idx) {
        final bus = _buses[idx];
        final route = bus['assigned_route'] as Map<String, dynamic>?;
        return Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.grey.shade300),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(bus['bus_number'] ?? '', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  Row(
                    children: [
                      IconButton(icon: const Icon(Icons.edit, color: kPrimaryBlue), onPressed: () => _showAddEditBusModal(bus)),
                      IconButton(icon: const Icon(Icons.delete, color: Colors.red), onPressed: () => _deleteBus(bus)),
                    ],
                  )
                ],
              ),
              Text('Driver: ${bus['driver_name'] ?? 'Unassigned'} (${bus['driver_phone'] ?? '—'})'),
              Text('GPS Device ID: ${bus['device_id'] ?? '—'}'),
              Text('Capacity: ${bus['capacity'] ?? 40} seats  |  Odometer: ${bus['current_odometer_km'] ?? 0} km'),
              const SizedBox(height: 4),
              route == null
                  ? const Text('Route: Unassigned', style: TextStyle(color: Colors.grey, fontStyle: FontStyle.italic, fontSize: 12))
                  : Text(
                      'Route: ${route['route_name']} (${route['traffic_level'] ?? 'medium'} traffic, ${route['road_quality'] ?? 'average'} road, ${route['speed_breaker_count'] ?? 0} breakers, ${route['sharp_turn_count'] ?? 0} turns)',
                      style: const TextStyle(fontSize: 12, color: kPrimaryBlue, fontWeight: FontWeight.w500),
                    ),
            ],
          ),
        );
      },
    );
  }
}
