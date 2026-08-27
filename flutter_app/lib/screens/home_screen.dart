import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'tracking_screen.dart';
import 'driver_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final supabase = Supabase.instance.client;
  String _role = '';
  Map<String, dynamic>? _userData;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadUserRole();
  }

  Future<void> _loadUserRole() async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) {
      setState(() => _loading = false);
      return;
    }

    try {
      // Fetch user role from user_roles table
      final roleData = await supabase
          .from('user_roles')
          .select('*, buses(*), schools(*)')
          .eq('user_id', userId)
          .single();

      setState(() {
        _role = roleData['role'];
        _userData = roleData;
        _loading = false;
      });
    } catch (e) {
      // No matching row in user_roles (or another fetch error) —
      // show a clear message instead of spinning forever.
      setState(() {
        _role = '';
        _loading = false;
      });
    }
  }

  void _logout() async {
    await supabase.auth.signOut();
    if (mounted) {
      Navigator.pushReplacementNamed(context, '/login');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    // Route to correct screen based on role
    if (_role == 'driver') {
      return _DriverHome(userData: _userData!, onLogout: _logout);
    } else if (_role == 'parent') {
      return _ParentHome(userData: _userData!, onLogout: _logout);
    } else if (_role == 'admin') {
      return _AdminHome(userData: _userData!, onLogout: _logout);
    }

    return const Scaffold(
      body: Center(child: Text('Role not assigned. Contact your school admin.')),
    );
  }
}

// ─── PARENT HOME ────────────────────────────────────────────────
class _ParentHome extends StatelessWidget {
  final Map<String, dynamic> userData;
  final VoidCallback onLogout;

  const _ParentHome({required this.userData, required this.onLogout});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text('BusTrack', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: const Color(0xFF1E6BFF),
        foregroundColor: Colors.white,
        actions: [
          IconButton(icon: const Icon(Icons.logout), onPressed: onLogout),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Greeting
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF1E6BFF), Color(0xFF0EA5E9)],
                ),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Good Morning!',
                      style: TextStyle(color: Colors.white70, fontSize: 14)),
                  const SizedBox(height: 4),
                  Text(
                    userData['schools']?['name'] ?? 'Your School',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 28),
            const Text('Your Children\'s Buses',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 12),

            // Bus card — tap to track
            _BusCard(
              busNumber: userData['buses']?['bus_number'] ?? 'N/A',
              driverName: userData['buses']?['driver_name'] ?? 'N/A',
              onTrack: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => TrackingScreen(
                      busId: userData['bus_id'],
                      busNumber: userData['buses']?['bus_number'] ?? '',
                      stopId: userData['stop_id'],
                    ),
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

class _BusCard extends StatelessWidget {
  final String busNumber;
  final String driverName;
  final VoidCallback onTrack;

  const _BusCard({
    required this.busNumber,
    required this.driverName,
    required this.onTrack,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 10)
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFEFF6FF),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.directions_bus,
                color: Color(0xFF1E6BFF), size: 28),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(busNumber,
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 16)),
                Text('Driver: $driverName',
                    style: const TextStyle(color: Colors.grey, fontSize: 13)),
              ],
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF1E6BFF),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: onTrack,
            child: const Text('Track'),
          ),
        ],
      ),
    );
  }
}

// ─── DRIVER HOME ─────────────────────────────────────────────────
class _DriverHome extends StatelessWidget {
  final Map<String, dynamic> userData;
  final VoidCallback onLogout;

  const _DriverHome({required this.userData, required this.onLogout});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F172A),
        foregroundColor: Colors.white,
        title: const Text('BusTrack — Driver',
            style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          IconButton(icon: const Icon(Icons.logout), onPressed: onLogout),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Bus ${userData['buses']?['bus_number'] ?? ''}',
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 26,
                  fontWeight: FontWeight.bold),
            ),
            Text(
              userData['schools']?['name'] ?? '',
              style: const TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              height: 56,
              child: ElevatedButton.icon(
                icon: const Icon(Icons.wifi_tethering),
                label: const Text('Open Driver Mode',
                    style: TextStyle(fontSize: 16)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1E6BFF),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => DriverScreen(
                        busId: userData['bus_id'],
                        deviceId: 'PHONE_${userData['bus_id']}',
                        busNumber: userData['buses']?['bus_number'] ?? '',
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── ADMIN HOME ──────────────────────────────────────────────────
class _AdminHome extends StatelessWidget {
  final Map<String, dynamic> userData;
  final VoidCallback onLogout;

  const _AdminHome({required this.userData, required this.onLogout});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Admin Dashboard'),
        backgroundColor: const Color(0xFF1E6BFF),
        foregroundColor: Colors.white,
        actions: [
          IconButton(icon: const Icon(Icons.logout), onPressed: onLogout),
        ],
      ),
      body: const Center(
        child: Text(
          'Open the React Admin Panel\non your browser for full dashboard.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 16, color: Colors.grey),
        ),
      ),
    );
  }
}