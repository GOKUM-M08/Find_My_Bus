import 'package:flutter/material.dart';
import '../screens/admin_dashboard_screen.dart';
import '../screens/route_management_screen.dart';
import '../screens/route_optimizer_screen.dart';
import '../screens/register_student_screen.dart';
import '../screens/settings_screen.dart';

const Color kPrimaryBlue = Color(0xFF0052CC);
const Color kSecondaryBlue = Color(0xFF1E6BFF);
const Color kLightBlue = Color(0xFFE8F0FE);
const Color kTextPrimary = Color(0xFF0F172A);
const Color kTextSecondary = Color(0xFF64748B);

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

  void _navigateTo(BuildContext context, Widget screen, String routeName) {
    Navigator.pop(context); // Close drawer
    if (currentRoute == routeName) return; // Already on this screen

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => screen),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Drawer(
      backgroundColor: Colors.white,
      child: Column(
        children: [
          // Header
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(16, 48, 16, 20),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [kPrimaryBlue, Color(0xFF00338C)],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.directions_bus_rounded,
                          color: Colors.white, size: 24),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'BusTrack Admin',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              letterSpacing: -0.3,
                            ),
                          ),
                          Text(
                            schoolName,
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.8),
                              fontSize: 12,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Menu Items
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
              children: [
                _DrawerTile(
                  icon: Icons.map_rounded,
                  label: 'Dashboard',
                  subtitle: 'Live fleet overview & warnings',
                  isSelected: currentRoute == 'dashboard',
                  onTap: () => _navigateTo(
                    context,
                    AdminDashboardScreen(
                      schoolId: schoolId,
                      schoolName: schoolName,
                    ),
                    'dashboard',
                  ),
                ),
                _DrawerTile(
                  icon: Icons.directions_bus_filled_rounded,
                  label: 'Buses',
                  subtitle: 'Fleet list & vehicle profile',
                  isSelected: currentRoute == 'buses',
                  onTap: () => _navigateTo(
                    context,
                    AdminDashboardScreen(
                      schoolId: schoolId,
                      schoolName: schoolName,
                    ),
                    'dashboard',
                  ),
                ),
                _DrawerTile(
                  icon: Icons.alt_route_rounded,
                  label: 'Routes',
                  subtitle: 'Route builder & road metrics',
                  isSelected: currentRoute == 'routes',
                  onTap: () => _navigateTo(
                    context,
                    RouteManagementScreen(schoolId: schoolId),
                    'routes',
                  ),
                ),
                _DrawerTile(
                  icon: Icons.auto_awesome_rounded,
                  label: 'Route Optimizer',
                  subtitle: 'Hungarian algorithm & grid',
                  isSelected: currentRoute == 'optimizer',
                  onTap: () => _navigateTo(
                    context,
                    RouteOptimizerScreen(
                      schoolId: schoolId,
                      schoolName: schoolName,
                    ),
                    'optimizer',
                  ),
                ),
                _DrawerTile(
                  icon: Icons.school_rounded,
                  label: 'Students',
                  subtitle: 'Bus & stop registration',
                  isSelected: currentRoute == 'students',
                  onTap: () => _navigateTo(
                    context,
                    RegisterStudentScreen(schoolId: schoolId),
                    'students',
                  ),
                ),
                _DrawerTile(
                  icon: Icons.settings_rounded,
                  label: 'Settings',
                  subtitle: 'System health & support',
                  isSelected: currentRoute == 'settings',
                  onTap: () => _navigateTo(
                    context,
                    const SettingsScreen(),
                    'settings',
                  ),
                ),
              ],
            ),
          ),

          // Footer
          Container(
            padding: const EdgeInsets.all(16),
            decoration: const BoxDecoration(
              border: Border(top: BorderSide(color: Color(0xFFE2E8F0))),
            ),
            child: const Row(
              children: [
                Icon(Icons.verified_user_rounded,
                    size: 16, color: kSecondaryBlue),
                SizedBox(width: 8),
                Text(
                  'Enterprise Fleet Control',
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: kTextSecondary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DrawerTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String subtitle;
  final bool isSelected;
  final VoidCallback onTap;

  const _DrawerTile({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      decoration: BoxDecoration(
        color: isSelected ? kLightBlue : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
      ),
      child: ListTile(
        leading: Icon(
          icon,
          color: isSelected ? kPrimaryBlue : kTextSecondary,
          size: 22,
        ),
        title: Text(
          label,
          style: TextStyle(
            fontSize: 14,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
            color: isSelected ? kPrimaryBlue : kTextPrimary,
          ),
        ),
        subtitle: Text(
          subtitle,
          style: TextStyle(
            fontSize: 10,
            color: isSelected ? kPrimaryBlue.withValues(alpha: 0.8) : kTextSecondary,
          ),
        ),
        onTap: onTap,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }
}
