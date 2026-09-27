import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../widgets/admin_drawer.dart';

const Color kPrimaryBlue = Color(0xFF0052CC);

class FuelMileageScreen extends StatefulWidget {
  final String schoolId;
  final String schoolName;

  const FuelMileageScreen({
    super.key,
    required this.schoolId,
    required this.schoolName,
  });

  @override
  State<FuelMileageScreen> createState() => _FuelMileageScreenState();
}

class _FuelMileageScreenState extends State<FuelMileageScreen> {
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
      final data = await supabase
          .from('buses')
          .select('id, bus_number, driver_name, mileage_kmpl, diesel_price_per_l, diesel_tank_capacity, current_odometer_km')
          .eq('school_id', widget.schoolId)
          .order('bus_number');

      if (!mounted) return;
      setState(() {
        _buses = List<Map<String, dynamic>>.from(data);
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
        _errorMessage = 'Could not load fuel data: ${e.toString()}';
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

  void _showEditFuelModal(Map<String, dynamic> bus) {
    final formKey = GlobalKey<FormState>();

    final priceCtrl = TextEditingController(text: (bus['diesel_price_per_l'] ?? 90.0).toString());
    final mileageCtrl = TextEditingController(text: (bus['mileage_kmpl'] ?? 4.0).toString());
    final capacityCtrl = TextEditingController(text: (bus['diesel_tank_capacity'] ?? 100.0).toString());

    bool saving = false;
    String? modalError;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) {
          return AlertDialog(
            title: Text('Edit Fuel Baseline — ${bus['bus_number']}'),
            content: SingleChildScrollView(
              child: Container(
                width: 400,
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
                        controller: priceCtrl,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: 'Diesel Price per Liter (₹) *'),
                        validator: (v) {
                          final parsed = double.tryParse(v ?? '');
                          if (parsed == null || parsed <= 0) return 'Price must be greater than zero';
                          return null;
                        },
                      ),
                      const SizedBox(height: 10),
                      TextFormField(
                        controller: mileageCtrl,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: 'Baseline Efficiency Mileage (km/L) *'),
                        validator: (v) {
                          final parsed = double.tryParse(v ?? '');
                          if (parsed == null || parsed <= 0) return 'Mileage must be greater than zero';
                          return null;
                        },
                      ),
                      const SizedBox(height: 10),
                      TextFormField(
                        controller: capacityCtrl,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: 'Fuel Tank Capacity (Liters) *'),
                        validator: (v) {
                          final parsed = double.tryParse(v ?? '');
                          if (parsed == null || parsed <= 0) return 'Tank capacity must be greater than zero';
                          return null;
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ),
            actions: [
              TextButton(onPressed: saving ? null : () => Navigator.pop(ctx), child: const Text('Cancel')),
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

                        final price = double.parse(priceCtrl.text.trim());
                        final mileage = double.parse(mileageCtrl.text.trim());
                        final cap = double.parse(capacityCtrl.text.trim());

                        try {
                          await supabase.from('buses').update({
                            'diesel_price_per_l': price,
                            'mileage_kmpl': mileage,
                            'diesel_tank_capacity': cap,
                          }).eq('id', bus['id']);

                          await _logAudit('UPDATE_FUEL', bus['id'], 'Updated fuel settings for ${bus['bus_number']} (Price: ₹$price, Mileage: $mileage km/L)');

                          if (mounted) {
                            Navigator.pop(ctx);
                            _fetchBuses();
                          }
                        } catch (e) {
                          setModalState(() {
                            saving = false;
                            modalError = 'Failed to update fuel settings: ${e.toString()}';
                          });
                        }
                      },
                child: saving
                    ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : const Text('Save Baseline'),
              ),
            ],
          );
        },
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
        currentRoute: 'fuel',
      ),
      appBar: AppBar(
        title: Text('${widget.schoolName} — Fuel & Mileage Tracking'),
        backgroundColor: kPrimaryBlue,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _fetchBuses,
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
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.amber.shade50,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Colors.amber.shade200),
                        ),
                        child: Row(
                          children: const [
                            Icon(Icons.local_gas_station, color: Colors.amber, size: 28),
                            SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                'Fuel & Mileage Baseline Settings\n'
                                'These parameters serve as the data foundation for fuel consumption calculations and future diesel-fraud anomaly detection.',
                                style: TextStyle(fontSize: 13, color: Color(0xFF78350F)),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),
                      _buses.isEmpty
                          ? const Center(child: Text('No buses registered yet.'))
                          : ListView.separated(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              itemCount: _buses.length,
                              separatorBuilder: (_, __) => const SizedBox(height: 12),
                              itemBuilder: (context, idx) {
                                final bus = _buses[idx];
                                final price = (bus['diesel_price_per_l'] ?? 90.0) as num;
                                final mileage = (bus['mileage_kmpl'] ?? 4.0) as num;
                                final tank = (bus['diesel_tank_capacity'] ?? 100.0) as num;

                                return Container(
                                  padding: const EdgeInsets.all(16),
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(color: Colors.grey.shade300),
                                  ),
                                  child: Row(
                                    children: [
                                      const CircleAvatar(
                                        backgroundColor: Color(0xFFE8F0FE),
                                        child: Icon(Icons.local_gas_station_rounded, color: kPrimaryBlue),
                                      ),
                                      const SizedBox(width: 14),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              bus['bus_number'] ?? '',
                                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                                            ),
                                            const SizedBox(height: 2),
                                            Text('Driver: ${bus['driver_name'] ?? 'Unassigned'}'),
                                            const SizedBox(height: 4),
                                            Text('Fuel Price: ₹${price.toStringAsFixed(2)} / L'),
                                            Text('Admin Baseline Efficiency: ${mileage.toStringAsFixed(1)} km/L'),
                                            Text('Tank Capacity: ${tank.toStringAsFixed(0)} Liters'),
                                          ],
                                        ),
                                      ),
                                      ElevatedButton.icon(
                                        style: ElevatedButton.styleFrom(backgroundColor: kPrimaryBlue, foregroundColor: Colors.white),
                                        onPressed: () => _showEditFuelModal(bus),
                                        icon: const Icon(Icons.edit, size: 16),
                                        label: const Text('Edit Baseline'),
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                    ],
                  ),
                ),
    );
  }
}
