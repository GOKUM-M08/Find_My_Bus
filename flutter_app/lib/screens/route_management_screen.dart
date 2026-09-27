import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../widgets/admin_drawer.dart';

const Color kPrimaryBlue = Color(0xFF0052CC);

class RouteManagementScreen extends StatefulWidget {
  final String schoolId;
  final String schoolName;

  const RouteManagementScreen({
    super.key,
    required this.schoolId,
    required this.schoolName,
  });

  @override
  State<RouteManagementScreen> createState() => _RouteManagementScreenState();
}

class _RouteManagementScreenState extends State<RouteManagementScreen> {
  final supabase = Supabase.instance.client;
  List<Map<String, dynamic>> _routes = [];
  List<Map<String, dynamic>> _buses = [];
  bool _loading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _fetchData();
  }

  Future<void> _fetchData() async {
    setState(() {
      _loading = true;
      _errorMessage = null;
    });

    try {
      final routeRows = await supabase
          .from('routes')
          .select('*, stops(*)')
          .eq('school_id', widget.schoolId)
          .order('route_name');

      final busRows = await supabase
          .from('buses')
          .select('id, bus_number, driver_name')
          .eq('school_id', widget.schoolId);

      if (!mounted) return;
      setState(() {
        _routes = List<Map<String, dynamic>>.from(routeRows);
        _buses = List<Map<String, dynamic>>.from(busRows);
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
        _errorMessage = 'Could not load routes: ${e.toString()}';
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
        'target_entity': 'routes',
        'target_id': targetId,
        'details': details,
      });
    } catch (_) {}
  }

  Future<void> _reassignBusForRoute(String routeId, String? newBusId) async {
    try {
      await supabase.from('routes').update({'bus_id': newBusId}).eq('id', routeId);
      await _logAudit('REASSIGN_ROUTE', routeId, 'Reassigned bus ID $newBusId to route $routeId');
      _fetchData();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Route bus assignment updated immediately!')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to reassign bus: ${e.toString()}'), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _showAddEditRouteModal([Map<String, dynamic>? existingRoute]) {
    final formKey = GlobalKey<FormState>();
    final isEdit = existingRoute != null;

    final routeNameCtrl = TextEditingController(text: existingRoute?['route_name'] ?? '');
    final speedBreakerCtrl = TextEditingController(text: (existingRoute?['speed_breaker_count'] ?? 0).toString());
    final sharpTurnCtrl = TextEditingController(text: (existingRoute?['sharp_turn_count'] ?? 0).toString());
    String selectedTrafficLevel = (existingRoute?['traffic_level'] as String?)?.toLowerCase() ?? 'medium';
    String selectedRoadQuality = (existingRoute?['road_quality'] as String?)?.toLowerCase() ?? 'average';
    if (!['low', 'medium', 'high'].contains(selectedTrafficLevel)) selectedTrafficLevel = 'medium';
    if (!['good', 'average', 'poor'].contains(selectedRoadQuality)) selectedRoadQuality = 'average';

    String? selectedBusId = existingRoute?['bus_id'];

    List<Map<String, dynamic>> stops = [];
    if (existingRoute != null && existingRoute['stops'] != null) {
      final rawStops = List<Map<String, dynamic>>.from(existingRoute['stops']);
      rawStops.sort((a, b) => (a['stop_order'] as int? ?? 0).compareTo(b['stop_order'] as int? ?? 0));
      stops = rawStops.map((s) => Map<String, dynamic>.from(s)).toList();
    }

    bool saving = false;
    String? modalError;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) {
          return AlertDialog(
            title: Text(isEdit ? 'Edit Route & Conditions' : 'Create New Route'),
            content: SingleChildScrollView(
              child: Container(
                width: 550,
                child: Form(
                  key: formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
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
                        controller: routeNameCtrl,
                        decoration: const InputDecoration(labelText: 'Route Name * (e.g. Morning Pickup North Zone)'),
                        validator: (v) => (v == null || v.trim().isEmpty) ? 'Route name is required' : null,
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        value: selectedBusId,
                        decoration: const InputDecoration(labelText: 'Assigned Bus Vehicle'),
                        items: [
                          const DropdownMenuItem<String>(value: null, child: Text('No Bus Assigned')),
                          ..._buses.map((b) => DropdownMenuItem<String>(
                                value: b['id'] as String,
                                child: Text('${b['bus_number']} (${b['driver_name'] ?? 'No driver'})'),
                              )),
                        ],
                        onChanged: (val) => setModalState(() => selectedBusId = val),
                      ),
                      const SizedBox(height: 16),
                      const Text('Route Condition Parameters', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: kPrimaryBlue)),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: speedBreakerCtrl,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(labelText: 'Speed Breakers (>= 0) *'),
                              validator: (v) {
                                final val = int.tryParse(v ?? '');
                                if (val == null || val < 0) return 'Cannot be negative';
                                return null;
                              },
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextFormField(
                              controller: sharpTurnCtrl,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(labelText: 'Sharp Turns (>= 0) *'),
                              validator: (v) {
                                final val = int.tryParse(v ?? '');
                                if (val == null || val < 0) return 'Cannot be negative';
                                return null;
                              },
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              value: selectedTrafficLevel,
                              decoration: const InputDecoration(labelText: 'Traffic Level'),
                              items: const [
                                DropdownMenuItem(value: 'low', child: Text('Low (1.0x)')),
                                DropdownMenuItem(value: 'medium', child: Text('Medium (1.15x)')),
                                DropdownMenuItem(value: 'high', child: Text('High (1.30x)')),
                              ],
                              onChanged: (v) => setModalState(() => selectedTrafficLevel = v ?? 'medium'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              value: selectedRoadQuality,
                              decoration: const InputDecoration(labelText: 'Road Quality'),
                              items: const [
                                DropdownMenuItem(value: 'good', child: Text('Good (1.0x)')),
                                DropdownMenuItem(value: 'average', child: Text('Average (1.10x)')),
                                DropdownMenuItem(value: 'poor', child: Text('Poor (1.25x)')),
                              ],
                              onChanged: (v) => setModalState(() => selectedRoadQuality = v ?? 'average'),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Ordered Route Stops *', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                          TextButton.icon(
                            onPressed: () {
                              setModalState(() {
                                stops.add({
                                  'stop_name': '',
                                  'latitude': 13.0827,
                                  'longitude': 80.2707,
                                  'stop_order': stops.length + 1,
                                  'expected_time': '07:30 AM',
                                });
                              });
                            },
                            icon: const Icon(Icons.add_location),
                            label: const Text('Add Stop'),
                          ),
                        ],
                      ),
                      if (stops.isEmpty)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 12),
                          child: Text('No stops added yet. Click "Add Stop" above.', style: TextStyle(color: Colors.grey, fontSize: 13)),
                        ),
                      ...stops.asMap().entries.map((entry) {
                        final idx = entry.key;
                        final stop = entry.value;
                        final nameCtrl = TextEditingController(text: stop['stop_name']);
                        final latCtrl = TextEditingController(text: stop['latitude']?.toString() ?? '13.0827');
                        final lonCtrl = TextEditingController(text: stop['longitude']?.toString() ?? '80.2707');
                        final timeCtrl = TextEditingController(text: stop['expected_time'] ?? '');

                        return Card(
                          margin: const EdgeInsets.symmetric(vertical: 6),
                          elevation: 1,
                          child: Padding(
                            padding: const EdgeInsets.all(10),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text('Stop #${idx + 1}', style: const TextStyle(fontWeight: FontWeight.bold, color: kPrimaryBlue)),
                                    IconButton(
                                      icon: const Icon(Icons.delete_outline, color: Colors.red, size: 20),
                                      onPressed: () {
                                        setModalState(() {
                                          stops.removeAt(idx);
                                        });
                                      },
                                    )
                                  ],
                                ),
                                TextFormField(
                                  controller: nameCtrl,
                                  decoration: const InputDecoration(labelText: 'Stop Name *'),
                                  onChanged: (v) => stop['stop_name'] = v,
                                ),
                                Row(
                                  children: [
                                    Expanded(
                                      child: TextFormField(
                                        controller: latCtrl,
                                        keyboardType: TextInputType.number,
                                        decoration: const InputDecoration(labelText: 'Latitude (-90 to 90)'),
                                        onChanged: (v) => stop['latitude'] = double.tryParse(v) ?? 0.0,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: TextFormField(
                                        controller: lonCtrl,
                                        keyboardType: TextInputType.number,
                                        decoration: const InputDecoration(labelText: 'Longitude (-180 to 180)'),
                                        onChanged: (v) => stop['longitude'] = double.tryParse(v) ?? 0.0,
                                      ),
                                    ),
                                  ],
                                ),
                                TextFormField(
                                  controller: timeCtrl,
                                  decoration: const InputDecoration(labelText: 'Expected Time (e.g. 07:15 AM)'),
                                  onChanged: (v) => stop['expected_time'] = v,
                                ),
                              ],
                            ),
                          ),
                        );
                      }).toList(),
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
                        if (stops.isEmpty) {
                          setModalState(() => modalError = 'Please add at least one stop to the route.');
                          return;
                        }

                        // Validate coordinates
                        for (int i = 0; i < stops.length; i++) {
                          final lat = (stops[i]['latitude'] as num?)?.toDouble() ?? 0.0;
                          final lon = (stops[i]['longitude'] as num?)?.toDouble() ?? 0.0;
                          if (stops[i]['stop_name'].toString().trim().isEmpty) {
                            setModalState(() => modalError = 'Stop #${i + 1} has a blank name.');
                            return;
                          }
                          if (lat < -90 || lat > 90 || lon < -180 || lon > 180) {
                            setModalState(() => modalError = 'Stop #${i + 1} has invalid GPS coordinates.');
                            return;
                          }
                        }

                        setModalState(() {
                          saving = true;
                          modalError = null;
                        });

                        try {
                          final payload = {
                            'route_name': routeNameCtrl.text.trim(),
                            'bus_id': selectedBusId,
                            'speed_breaker_count': int.tryParse(speedBreakerCtrl.text) ?? 0,
                            'sharp_turn_count': int.tryParse(sharpTurnCtrl.text) ?? 0,
                            'traffic_level': selectedTrafficLevel,
                            'road_quality': selectedRoadQuality,
                          };

                          String routeId;
                          if (isEdit) {
                            routeId = existingRoute['id'];
                            await supabase.from('routes').update(payload).eq('id', routeId);

                            // 1. Identify IDs of stops kept in the form
                            final currentFormStopIds = stops
                                .where((s) => s['id'] != null)
                                .map((s) => s['id'].toString())
                                .toSet();

                            // 2. Safely handle stops removed from the form
                            final originalStops = List<Map<String, dynamic>>.from(existingRoute['stops'] ?? []);
                            for (final origStop in originalStops) {
                              final origId = origStop['id']?.toString();
                              if (origId != null && !currentFormStopIds.contains(origId)) {
                                // Unlink students assigned to this stop before deleting it
                                await supabase.from('students').update({'stop_id': null}).eq('stop_id', origId);
                                await supabase.from('stops').delete().eq('id', origId);
                              }
                            }

                            // 3. Update existing stops in-place and insert new stops
                            for (int i = 0; i < stops.length; i++) {
                              final s = stops[i];
                              final stopPayload = {
                                'route_id': routeId,
                                'stop_name': s['stop_name'].toString().trim(),
                                'latitude': (s['latitude'] as num).toDouble(),
                                'longitude': (s['longitude'] as num).toDouble(),
                                'stop_order': i + 1,
                                'expected_time': s['expected_time']?.toString().trim(),
                              };

                              if (s['id'] != null) {
                                await supabase.from('stops').update(stopPayload).eq('id', s['id']);
                              } else {
                                final newRes = await supabase.from('stops').insert(stopPayload).select();
                                if (newRes.isNotEmpty) {
                                  s['id'] = newRes[0]['id'];
                                }
                              }
                            }

                            await _logAudit('UPDATE_ROUTE', routeId, 'Updated route ${routeNameCtrl.text.trim()} (Breakers: ${speedBreakerCtrl.text}, Turns: ${sharpTurnCtrl.text}, Traffic: $selectedTrafficLevel)');
                          } else {
                            final insertPayload = {...payload, 'school_id': widget.schoolId};
                            final res = await supabase.from('routes').insert(insertPayload).select();
                            routeId = res[0]['id'];

                            final stopsPayload = stops.asMap().entries.map((e) {
                              final idx = e.key;
                              final s = e.value;
                              return {
                                'route_id': routeId,
                                'stop_name': s['stop_name'].toString().trim(),
                                'latitude': (s['latitude'] as num).toDouble(),
                                'longitude': (s['longitude'] as num).toDouble(),
                                'stop_order': idx + 1,
                                'expected_time': s['expected_time']?.toString().trim(),
                              };
                            }).toList();

                            await supabase.from('stops').insert(stopsPayload);
                            await _logAudit('CREATE_ROUTE', routeId, 'Created route ${routeNameCtrl.text.trim()}');
                          }

                          if (mounted) {
                            Navigator.pop(ctx);
                            _fetchData();
                          }
                        } catch (e) {
                          setModalState(() {
                            saving = false;
                            modalError = 'Failed to save route: ${e.toString()}';
                          });
                        }
                      },
                child: saving
                    ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : Text(isEdit ? 'Save Route & Stops' : 'Create Route'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _deleteRoute(Map<String, dynamic> route) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirm Route Deletion'),
        content: Text('Are you sure you want to delete route "${route['route_name']}" and all associated stops? This action cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete Route'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await supabase.from('stops').delete().eq('route_id', route['id']);
        await supabase.from('routes').delete().eq('id', route['id']);
        await _logAudit('DELETE_ROUTE', route['id'], 'Deleted route ${route['route_name']}');
        _fetchData();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Route "${route['route_name']}" deleted.')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to delete route: ${e.toString()}'), backgroundColor: Colors.red),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F9FC),
      drawer: AdminDrawer(
        schoolId: widget.schoolId,
        schoolName: widget.schoolName,
        currentRoute: 'routes',
      ),
      appBar: AppBar(
        title: Text('${widget.schoolName} — Route Management'),
        backgroundColor: kPrimaryBlue,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: 'Create New Route',
            onPressed: () => _showAddEditRouteModal(),
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => _fetchData(),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: kPrimaryBlue))
          : _errorMessage != null
              ? Center(child: Text(_errorMessage!, style: const TextStyle(color: Colors.red)))
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Configured Transport Routes', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                          ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(backgroundColor: kPrimaryBlue, foregroundColor: Colors.white),
                            onPressed: () => _showAddEditRouteModal(),
                            icon: const Icon(Icons.add_location_alt),
                            label: const Text('Create Route'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      _routes.isEmpty
                          ? const Center(child: Padding(padding: EdgeInsets.all(32), child: Text('No routes created yet.')))
                          : ListView.separated(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              itemCount: _routes.length,
                              separatorBuilder: (_, __) => const SizedBox(height: 12),
                              itemBuilder: (context, idx) => _buildRouteCard(_routes[idx]),
                            ),
                    ],
                  ),
                ),
    );
  }

  Widget _buildRouteCard(Map<String, dynamic> route) {
    final stops = List<Map<String, dynamic>>.from(route['stops'] ?? []);
    stops.sort((a, b) => (a['stop_order'] as int? ?? 0).compareTo(b['stop_order'] as int? ?? 0));

    final currentBusId = route['bus_id'];

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
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  route['route_name'] ?? 'Unnamed Route',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: kPrimaryBlue),
                ),
              ),
              Row(
                children: [
                  IconButton(icon: const Icon(Icons.edit, color: kPrimaryBlue), onPressed: () => _showAddEditRouteModal(route)),
                  IconButton(icon: const Icon(Icons.delete, color: Colors.red), onPressed: () => _deleteRoute(route)),
                ],
              )
            ],
          ),
          Row(
            children: [
              _buildConditionBadge('Traffic: ${route['traffic_level'] ?? 'medium'}', Colors.orange.shade800, Colors.orange.shade50),
              const SizedBox(width: 6),
              _buildConditionBadge('Quality: ${route['road_quality'] ?? 'average'}', Colors.blue.shade800, Colors.blue.shade50),
              const SizedBox(width: 6),
              _buildConditionBadge('Breakers: ${route['speed_breaker_count'] ?? 0}', Colors.purple.shade800, Colors.purple.shade50),
              const SizedBox(width: 6),
              _buildConditionBadge('Turns: ${route['sharp_turn_count'] ?? 0}', Colors.teal.shade800, Colors.teal.shade50),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              const Text('Assigned Bus: ', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
              const SizedBox(width: 8),
              DropdownButton<String>(
                value: currentBusId,
                hint: const Text('Select Bus'),
                items: [
                  const DropdownMenuItem<String>(value: null, child: Text('Unassigned')),
                  ..._buses.map((b) => DropdownMenuItem<String>(
                        value: b['id'] as String,
                        child: Text('${b['bus_number']} (${b['driver_name'] ?? 'No driver'})'),
                      )),
                ],
                onChanged: (newBusId) => _reassignBusForRoute(route['id'], newBusId),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text('Route Stops (${stops.length}):', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
          const SizedBox(height: 4),
          if (stops.isEmpty)
            const Text('No stops configured.', style: TextStyle(color: Colors.grey, fontSize: 12))
          else
            Column(
              children: stops.map((s) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(color: kPrimaryBlue.withOpacity(0.1), borderRadius: BorderRadius.circular(4)),
                        child: Text('Stop ${s['stop_order']}', style: const TextStyle(color: kPrimaryBlue, fontSize: 11, fontWeight: FontWeight.bold)),
                      ),
                      const SizedBox(width: 8),
                      Expanded(child: Text(s['stop_name'] ?? 'Unnamed stop', style: const TextStyle(fontSize: 13))),
                      Text(s['expected_time'] ?? '', style: const TextStyle(color: Colors.grey, fontSize: 12)),
                    ],
                  ),
                );
              }).toList(),
            ),
        ],
      ),
    );
  }

  Widget _buildConditionBadge(String label, Color textColor, Color bgColor) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(color: bgColor, borderRadius: BorderRadius.circular(4)),
      child: Text(label, style: TextStyle(color: textColor, fontSize: 11, fontWeight: FontWeight.w600)),
    );
  }
}
