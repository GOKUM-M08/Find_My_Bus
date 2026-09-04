import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'config.dart';
import 'route_profile_screen.dart';

const Color kPrimaryBlue = Color(0xFF0052CC);
const Color kLightBlue = Color(0xFFE8F0FE);
const Color kBackgroundSlate = Color(0xFFF7F9FC);
const Color kCardBorder = Color(0xFFE2E8F0);
const Color kTextPrimary = Color(0xFF0F172A);
const Color kTextSecondary = Color(0xFF64748B);

class RouteManagementScreen extends StatefulWidget {
  final String schoolId;

  const RouteManagementScreen({super.key, required this.schoolId});

  @override
  State<RouteManagementScreen> createState() => _RouteManagementScreenState();
}

class _RouteManagementScreenState extends State<RouteManagementScreen> {
  List<dynamic> _routes = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _fetchRoutes();
  }

  Future<void> _fetchRoutes() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final uri = Uri.parse('$kBackendBaseUrl/admin/optimize-routes')
          .replace(queryParameters: {'school_id': widget.schoolId});
      final res = await http.get(uri).timeout(const Duration(seconds: 10));

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        if (mounted) {
          setState(() {
            _routes = (data['routes'] as List?) ?? [];
            _loading = false;
          });
        }
      } else {
        throw Exception('Server returned ${res.statusCode}');
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Failed to load routes: $e';
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBackgroundSlate,
      appBar: AppBar(
        backgroundColor: kPrimaryBlue,
        foregroundColor: Colors.white,
        title: const Text('Route Management'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: kPrimaryBlue))
          : _error != null
              ? Center(child: Text(_error!))
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _routes.length,
                  itemBuilder: (context, index) {
                    final r = _routes[index] as Map<String, dynamic>;
                    final name = r['label'] ?? r['route_name'] ?? 'Route #${index + 1}';
                    final traffic = r['traffic_level'] ?? 'Unentered';

                    return Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: kCardBorder),
                      ),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: kLightBlue,
                          child: const Icon(Icons.alt_route_rounded, color: kPrimaryBlue),
                        ),
                        title: Text(
                          name,
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 16),
                        ),
                        subtitle: Text('Traffic: $traffic'),
                        trailing: const Icon(Icons.chevron_right_rounded),
                        onTap: () async {
                          final updated = await Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => RouteProfileScreen(route: r),
                            ),
                          );
                          if (updated == true) {
                            _fetchRoutes();
                          }
                        },
                      ),
                    );
                  },
                ),
    );
  }
}
