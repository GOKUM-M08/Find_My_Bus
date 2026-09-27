import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../screens/admin_dashboard_screen.dart';
import '../screens/bus_profile_screen.dart';
import '../screens/route_management_screen.dart';
import '../screens/register_student_screen.dart';
import '../screens/fuel_mileage_screen.dart';
import '../screens/route_optimizer_screen.dart';
import '../screens/settings_screen.dart';
import '../screens/admin_login_screen.dart';

const Color kPrimaryBlue = Color(0xFF0052CC);
const Color kDarkBlue = Color(0xFF00338C);

class AdminDrawer extends StatelessWidget {
  final String schoolId;
  final String schoolName;
  final String currentRoute;

  const AdminDrawer({
    super.key,
    required this.schoolId,
    required this.schoolName,
    required this.currentRoute,
  });

  void _navigate(BuildContext context, Widget screen, String routeName) {
    if (currentRoute == routeName) {
      Navigator.pop(context); // Close drawer if already on target screen
      return;
    }
    Navigator.pop(context); // Close drawer
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => screen),
    );
  }

  Future<void> _logout(BuildContext context) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirm Logout'),
        content: const Text('Are you sure you want to log out of the Admin Console?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Log Out'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await Supabase.instance.client.auth.signOut();
      if (context.mounted) {
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (_) => const AdminLoginScreen()),
          (route) => false,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = Supabase.instance.client.auth.currentUser;
    final adminEmail = user?.email ?? 'admin@school.edu';

    return Drawer(
      child: Column(
        children: [
          DrawerHeader(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [kPrimaryBlue, kDarkBlue],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: SizedBox(
              width: double.infinity,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const CircleAvatar(
                    backgroundColor: Colors.white24,
                    radius: 24,
                    child: Icon(Icons.admin_panel_settings, color: Colors.white, size: 28),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    schoolName,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    adminEmail,
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: 8),
              children: [
                _buildNavItem(
                  context,
                  icon: Icons.dashboard_rounded,
                  label: 'Dashboard Overview',
                  route: 'dashboard',
                  screen: AdminDashboardScreen(schoolId: schoolId, schoolName: schoolName),
                ),
                _buildNavItem(
                  context,
                  icon: Icons.directions_bus_rounded,
                  label: 'Bus Fleet Management',
                  route: 'buses',
                  screen: BusProfileScreen(schoolId: schoolId, schoolName: schoolName),
                ),
                _buildNavItem(
                  context,
                  icon: Icons.alt_route_rounded,
                  label: 'Route Builder & Buses',
                  route: 'routes',
                  screen: RouteManagementScreen(schoolId: schoolId, schoolName: schoolName),
                ),
                _buildNavItem(
                  context,
                  icon: Icons.school_rounded,
                  label: 'Student Transport List',
                  route: 'students',
                  screen: RegisterStudentScreen(schoolId: schoolId, schoolName: schoolName),
                ),
                _buildNavItem(
                  context,
                  icon: Icons.local_gas_station_rounded,
                  label: 'Fuel & Mileage Tracking',
                  route: 'fuel',
                  screen: FuelMileageScreen(schoolId: schoolId, schoolName: schoolName),
                ),
                _buildNavItem(
                  context,
                  icon: Icons.auto_awesome_rounded,
                  label: 'Route Optimizer Engine',
                  route: 'optimizer',
                  screen: RouteOptimizerScreen(schoolId: schoolId, schoolName: schoolName),
                ),
                const Divider(height: 24),
                _buildNavItem(
                  context,
                  icon: Icons.settings_rounded,
                  label: 'Settings & Audit Logs',
                  route: 'settings',
                  screen: SettingsScreen(schoolId: schoolId, schoolName: schoolName),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: Colors.grey.shade200)),
            ),
            child: ListTile(
              leading: const Icon(Icons.logout_rounded, color: Colors.red),
              title: const Text('Log Out', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
              onTap: () => _logout(context),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNavItem(
    BuildContext context, {
    required IconData icon,
    required String label,
    required String route,
    required Widget screen,
  }) {
    final selected = currentRoute == route;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
      decoration: BoxDecoration(
        color: selected ? kPrimaryBlue.withOpacity(0.1) : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
      ),
      child: ListTile(
        leading: Icon(icon, color: selected ? kPrimaryBlue : Colors.grey.shade700),
        title: Text(
          label,
          style: TextStyle(
            fontSize: 14,
            fontWeight: selected ? FontWeight.bold : FontWeight.normal,
            color: selected ? kPrimaryBlue : Colors.grey.shade800,
          ),
        ),
        onTap: () => _navigate(context, screen, route),
      ),
    );
  }
}
