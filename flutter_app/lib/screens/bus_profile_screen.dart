import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'config.dart';

const Color kPrimaryBlue = Color(0xFF0052CC);
const Color kSecondaryBlue = Color(0xFF1E6BFF);
const Color kLightBlue = Color(0xFFE8F0FE);
const Color kBackgroundSlate = Color(0xFFF7F9FC);
const Color kCardBorder = Color(0xFFE2E8F0);
const Color kTextPrimary = Color(0xFF0F172A);
const Color kTextSecondary = Color(0xFF64748B);
const Color kSuccessGreen = Color(0xFF10B981);
const Color kWarningAmber = Color(0xFFF59E0B);
const Color kDangerRed = Color(0xFFEF4444);

class BusProfileScreen extends StatefulWidget {
  final Map<String, dynamic> bus;

  const BusProfileScreen({super.key, required this.bus});

  @override
  State<BusProfileScreen> createState() => _BusProfileScreenState();
}

class _BusProfileScreenState extends State<BusProfileScreen> {
  String? _busType;
  late TextEditingController _ageController;
  bool _suitableForNarrow = false;
  bool _saving = false;
  bool _simulating = false;

  @override
  void initState() {
    super.initState();
    _busType = widget.bus['bus_type']?.toString() ?? 'medium';
    _ageController = TextEditingController(
        text: widget.bus['age_years']?.toString() ?? '');
    _suitableForNarrow = widget.bus['suitable_for_narrow_roads'] == true;
  }

  @override
  void dispose() {
    _ageController.dispose();
    super.dispose();
  }

  Future<void> _saveAttributes() async {
    setState(() => _saving = true);
    final busId = widget.bus['id'];

    try {
      final res = await http
          .put(
            Uri.parse('$kBackendBaseUrl/admin/buses/$busId/attributes'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'bus_type': _busType,
              'age_years': int.tryParse(_ageController.text),
              'suitable_for_narrow_roads': _suitableForNarrow,
            }),
          )
          .timeout(const Duration(seconds: 10));

      if (res.statusCode == 200) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Bus attributes updated successfully!'),
              backgroundColor: kSuccessGreen,
            ),
          );
          Navigator.pop(context, true);
        }
      } else {
        throw Exception('Server error: ${res.statusCode}');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to update bus attributes: $e'),
            backgroundColor: kDangerRed,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _runWhatIfSimulation() async {
    setState(() => _simulating = true);
    final busId = widget.bus['id'];

    try {
      final res = await http
          .post(
            Uri.parse('$kBackendBaseUrl/admin/simulate-bus-unavailable/$busId'),
          )
          .timeout(const Duration(seconds: 15));

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        if (mounted) {
          _showSimulationDialog(data);
        }
      } else {
        throw Exception('Simulation returned ${res.statusCode}');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('What-if simulation failed: $e'),
            backgroundColor: kDangerRed,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _simulating = false);
    }
  }

  void _showSimulationDialog(Map<String, dynamic> data) {
    final busLabel = widget.bus['label'] ?? widget.bus['bus_number'] ?? 'Bus';
    final costDelta = (data['cost_delta'] as num?)?.toDouble() ?? 0.0;
    final summary = data['summary']?.toString() ?? '';

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            const Icon(Icons.science_rounded, color: kSecondaryBlue),
            const SizedBox(width: 8),
            Text('What-If Simulation: $busLabel'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Simulated scenario if $busLabel becomes unavailable or breaks down:',
              style: const TextStyle(fontSize: 13, height: 1.4),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: costDelta > 0
                    ? kWarningAmber.withOpacity(0.1)
                    : kSuccessGreen.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: costDelta > 0
                      ? kWarningAmber.withOpacity(0.4)
                      : kSuccessGreen.withOpacity(0.4),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Fuel Cost Change: ₹${costDelta > 0 ? "+$costDelta" : costDelta.toStringAsFixed(2)}',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                      color: costDelta > 0 ? kWarningAmber : kSuccessGreen,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(summary,
                      style: const TextStyle(fontSize: 12, color: kTextPrimary)),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final busLabel = widget.bus['label'] ?? widget.bus['bus_number'] ?? 'Bus Profile';
    final capacity = widget.bus['capacity'] ?? 40;
    final mileage = widget.bus['mileage_kmpl'] ?? 4.0;
    final condition = widget.bus['condition_score'] ?? 1.0;

    String suitSummary = 'Suitable for urban arterial routes.';
    if (_busType == 'large') {
      suitSummary = _suitableForNarrow
          ? 'Suitable for major avenues & narrow residential connectors.'
          : 'Suitable for major avenues; NOT recommended for narrow roads or dense speed breaker zones.';
    } else if (_busType == 'small') {
      suitSummary = 'Highly agile; suited for narrow streets and dense neighborhood stops.';
    }

    return Scaffold(
      backgroundColor: kBackgroundSlate,
      appBar: AppBar(
        backgroundColor: kPrimaryBlue,
        foregroundColor: Colors.white,
        title: Text(busLabel),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Header Card
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: kCardBorder),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      busLabel,
                      style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: kTextPrimary),
                    ),
                    Chip(
                      backgroundColor: kLightBlue,
                      label: Text(
                        'Capacity: $capacity Seats',
                        style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: kPrimaryBlue),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  'Suitability Summary: $suitSummary',
                  style: const TextStyle(fontSize: 12, color: kTextSecondary),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // PHASE 3 ACTION: WHAT-IF SIMULATION BUTTON
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: kSecondaryBlue.withOpacity(0.3)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.science_rounded, color: kSecondaryBlue),
                    SizedBox(width: 8),
                    Text(
                      'What-If Fleet Simulation',
                      style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: kTextPrimary),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                const Text(
                  'Simulate global fleet impact if this bus becomes unavailable or breaks down.',
                  style: TextStyle(fontSize: 11, color: kTextSecondary),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  height: 44,
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: kSecondaryBlue,
                      side: const BorderSide(color: kSecondaryBlue),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                    onPressed: _simulating ? null : _runWhatIfSimulation,
                    icon: _simulating
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: kSecondaryBlue),
                          )
                        : const Icon(Icons.do_not_disturb_on_rounded, size: 18),
                    label: const Text(
                      'Simulate Bus Unavailable',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // Attributes Edit Form
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: kCardBorder),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Vehicle Attributes & Chassis Type',
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: kTextPrimary),
                ),
                const SizedBox(height: 16),

                // Bus Type
                const Text('Bus Chassis Category',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                DropdownButtonFormField<String>(
                  initialValue: _busType,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    contentPadding:
                        EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'large', child: Text('Large Bus (50+ Capacity)')),
                    DropdownMenuItem(value: 'medium', child: Text('Medium Bus (30-45 Capacity)')),
                    DropdownMenuItem(value: 'small', child: Text('Small Minibus / Van (<30 Capacity)')),
                  ],
                  onChanged: (v) => setState(() => _busType = v),
                ),

                const SizedBox(height: 14),

                // Age in Years
                TextField(
                  controller: _ageController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Vehicle Age in Years',
                    border: OutlineInputBorder(),
                  ),
                ),

                const SizedBox(height: 14),

                // Suitable for Narrow Roads
                SwitchListTile(
                  title: const Text('Suitable for Narrow Roads'),
                  subtitle: const Text('Flag if chassis can maneuver narrow suburban roads'),
                  value: _suitableForNarrow,
                  onChanged: (v) => setState(() => _suitableForNarrow = v),
                  activeColor: kSecondaryBlue,
                ),

                const SizedBox(height: 20),

                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: kPrimaryBlue,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                    onPressed: _saving ? null : _saveAttributes,
                    icon: _saving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.save_rounded),
                    label: const Text(
                      'Save Bus Attributes',
                      style:
                          TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
