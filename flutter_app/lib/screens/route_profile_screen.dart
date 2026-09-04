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

class RouteProfileScreen extends StatefulWidget {
  final Map<String, dynamic> route;

  const RouteProfileScreen({super.key, required this.route});

  @override
  State<RouteProfileScreen> createState() => _RouteProfileScreenState();
}

class _RouteProfileScreenState extends State<RouteProfileScreen> {
  late TextEditingController _trafficController;
  late TextEditingController _breakersController;
  late TextEditingController _narrowController;
  late TextEditingController _qualityController;
  late TextEditingController _speedController;
  late TextEditingController _peakController;

  String? _trafficLevel;
  String? _roadQuality;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _trafficLevel = widget.route['traffic_level']?.toString();
    _roadQuality = widget.route['road_quality']?.toString();

    _breakersController = TextEditingController(
        text: widget.route['num_speed_breakers']?.toString() ?? '');
    _narrowController = TextEditingController(
        text: widget.route['num_narrow_road_sections']?.toString() ?? '');
    _speedController = TextEditingController(
        text: widget.route['avg_speed_kmph']?.toString() ?? '');
    _peakController = TextEditingController(
        text: widget.route['peak_congestion_window']?.toString() ?? '');
  }

  @override
  void dispose() {
    _breakersController.dispose();
    _narrowController.dispose();
    _speedController.dispose();
    _peakController.dispose();
    super.dispose();
  }

  double? _computeDifficulty() {
    if (_trafficLevel == null &&
        _breakersController.text.isEmpty &&
        _narrowController.text.isEmpty &&
        _roadQuality == null) {
      return null;
    }

    double tVal = _trafficLevel == 'high'
        ? 90
        : (_trafficLevel == 'medium' ? 50 : 10);
    double bVal = (int.tryParse(_breakersController.text) ?? 0) * 10.0;
    double nVal = (int.tryParse(_narrowController.text) ?? 0) * 25.0;
    double qVal =
        _roadQuality == 'poor' ? 90 : (_roadQuality == 'moderate' ? 50 : 10);

    double diff =
        0.30 * tVal + 0.25 * bVal.clamp(0, 100) + 0.25 * nVal.clamp(0, 100) + 0.20 * qVal;
    return diff.clamp(0, 100);
  }

  Future<void> _saveCondition() async {
    setState(() => _saving = true);
    final routeId = widget.route['id'];

    try {
      final res = await http
          .put(
            Uri.parse('$kBackendBaseUrl/admin/routes/$routeId/condition'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'traffic_level': _trafficLevel,
              'num_speed_breakers':
                  int.tryParse(_breakersController.text),
              'num_narrow_road_sections':
                  int.tryParse(_narrowController.text),
              'road_quality': _roadQuality,
              'avg_speed_kmph':
                  double.tryParse(_speedController.text),
              'peak_congestion_window': _peakController.text.isNotEmpty
                  ? _peakController.text
                  : null,
            }),
          )
          .timeout(const Duration(seconds: 10));

      if (res.statusCode == 200) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Route condition parameters updated successfully!'),
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
            content: Text('Failed to update route condition: $e'),
            backgroundColor: kDangerRed,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final routeName = widget.route['route_name'] ?? 'Route Profile';
    final distance = widget.route['distance_km'] ?? 0;
    final students = widget.route['student_count'] ?? 0;
    final difficulty = _computeDifficulty();

    return Scaffold(
      backgroundColor: kBackgroundSlate,
      appBar: AppBar(
        backgroundColor: kPrimaryBlue,
        foregroundColor: Colors.white,
        title: Text(routeName),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Route Summary Header Card
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
                      routeName,
                      style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: kTextPrimary),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: difficulty != null
                            ? Color.lerp(kSuccessGreen, kDangerRed, difficulty / 100)!.withOpacity(0.15)
                            : Colors.grey.shade200,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        difficulty != null
                            ? 'Difficulty: ${difficulty.toStringAsFixed(0)}/100'
                            : 'Difficulty: Unentered',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: difficulty != null
                              ? Color.lerp(kSuccessGreen, kDangerRed, difficulty / 100)
                              : kTextSecondary,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    _MetricBadge(
                        label: 'Distance',
                        value: '$distance km',
                        icon: Icons.alt_route),
                    const SizedBox(width: 8),
                    _MetricBadge(
                        label: 'Students',
                        value: '$students boarded',
                        icon: Icons.people),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // DATA HONESTY DISCLAIMER CARD
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: kWarningAmber.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: kWarningAmber.withOpacity(0.4)),
            ),
            child: const Row(
              children: [
                Icon(Icons.edit_note_rounded, color: kWarningAmber, size: 22),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'ADMIN-ENTERED FIELDS: These road condition measurements are manually entered by transport admins, not live sensor derived.',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: kTextPrimary,
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // Edit Form
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
                  'Road Condition Parameters',
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: kTextPrimary),
                ),
                const SizedBox(height: 16),

                // Traffic Level
                const Text('Traffic Level (Admin Estimate)',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                DropdownButtonFormField<String>(
                  initialValue: _trafficLevel,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'low', child: Text('Low Traffic')),
                    DropdownMenuItem(value: 'medium', child: Text('Medium Traffic')),
                    DropdownMenuItem(value: 'high', child: Text('High Traffic / Heavy Congestion')),
                  ],
                  onChanged: (v) => setState(() => _trafficLevel = v),
                ),

                const SizedBox(height: 14),

                // Speed Breakers
                TextField(
                  controller: _breakersController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Number of Speed Breakers (Manually Entered)',
                    border: OutlineInputBorder(),
                  ),
                ),

                const SizedBox(height: 14),

                // Narrow Road Sections
                TextField(
                  controller: _narrowController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Narrow Road Sections Count (Manually Entered)',
                    border: OutlineInputBorder(),
                  ),
                ),

                const SizedBox(height: 14),

                // Road Quality
                const Text('Road Quality Rating (Admin Estimate)',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                DropdownButtonFormField<String>(
                  initialValue: _roadQuality,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'good', child: Text('Good (Paved Smooth)')),
                    DropdownMenuItem(value: 'moderate', child: Text('Moderate (Potholes/Rough)')),
                    DropdownMenuItem(value: 'poor', child: Text('Poor (Unpaved/Severe Potholes)')),
                  ],
                  onChanged: (v) => setState(() => _roadQuality = v),
                ),

                const SizedBox(height: 14),

                // Avg Speed
                TextField(
                  controller: _speedController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Average Speed km/h (Admin Estimate)',
                    border: OutlineInputBorder(),
                  ),
                ),

                const SizedBox(height: 14),

                // Peak Congestion Window
                TextField(
                  controller: _peakController,
                  decoration: const InputDecoration(
                    labelText: 'Peak Congestion Window (e.g. 7:30-8:30 AM)',
                    border: OutlineInputBorder(),
                  ),
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
                    onPressed: _saving ? null : _saveCondition,
                    icon: _saving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.save_rounded),
                    label: const Text(
                      'Save Route Condition Data',
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

class _MetricBadge extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;

  const _MetricBadge(
      {required this.label, required this.value, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: kLightBlue.withOpacity(0.5),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Icon(icon, size: 16, color: kPrimaryBlue),
            const SizedBox(width: 6),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style:
                        const TextStyle(fontSize: 10, color: kTextSecondary)),
                Text(value,
                    style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: kTextPrimary)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
