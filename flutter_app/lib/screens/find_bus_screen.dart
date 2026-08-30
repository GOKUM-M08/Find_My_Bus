import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'login_screen.dart';
import 'stops_screen.dart';
import 'admin_login_screen.dart';

// Colors from main.dart
const Color PRIMARY_BLUE = Color(0xFF0052CC);
const Color SECONDARY_BLUE = Color(0xFF1E6BFF);
const Color LIGHT_BLUE = Color(0xFFE8F0FE);
const Color BACKGROUND_BLUE = Color(0xFFF7F9FC);

class FindBusScreen extends StatefulWidget {
  const FindBusScreen({super.key});

  @override
  State<FindBusScreen> createState() => _FindBusScreenState();
}

class _FindBusScreenState extends State<FindBusScreen> {
  final supabase = Supabase.instance.client;
  final TextEditingController _searchController = TextEditingController();
  Timer? _debounce;

  List<Map<String, dynamic>> _suggestions = [];
  List<Map<String, dynamic>> _browseBuses = [];
  Set<String> _liveBusIds = {};
  bool _searching = false;
  bool _loadingBrowse = true;

  @override
  void initState() {
    super.initState();
    _loadBrowseBuses();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  /// Shown before the parent types anything — a simple browsable list
  /// of buses, standing in for "recent searches" since there's no
  /// logged-in user to remember a history for.
  Future<void> _loadBrowseBuses() async {
    final result = await supabase
        .from('buses')
        .select('id, bus_number, bus_code, schools(name)')
        .order('bus_number')
        .limit(20);

    final liveBusIds = await _loadLiveBusIds(result);
    if (!mounted) return;
    setState(() {
      _browseBuses = List<Map<String, dynamic>>.from(result);
      _liveBusIds = liveBusIds;
      _loadingBrowse = false;
    });
  }

  Future<Set<String>> _loadLiveBusIds(List<dynamic> buses) async {
    final busIds = buses
        .map((bus) => bus['id']?.toString())
        .whereType<String>()
        .toList();
    if (busIds.isEmpty) return {};

    final locations = await supabase
        .from('live_location')
        .select('bus_id, timestamp')
        .inFilter('bus_id', busIds);
    final now = DateTime.now().toUtc();
    return locations
        .where((location) {
          final timestamp = location['timestamp'];
          if (timestamp == null) return false;
          return now.difference(DateTime.parse(timestamp).toUtc()).inSeconds < 60;
        })
        .map((location) => location['bus_id'].toString())
        .toSet();
  }

  void _onSearchChanged(String query) {
    _debounce?.cancel();
    if (query.trim().isEmpty) {
      setState(() => _suggestions = []);
      return;
    }
    // Small debounce so we're not firing a query on every keystroke.
    _debounce = Timer(const Duration(milliseconds: 300), () {
      _runSearch(query.trim());
    });
  }

  Future<void> _runSearch(String query) async {
    setState(() => _searching = true);

    // Search buses by number/code, and schools by name, in parallel —
    // combined into one suggestion list like WIMT mixes stations/trains.
    final busResults = await supabase
        .from('buses')
        .select('id, bus_number, bus_code, schools(name)')
        .or('bus_number.ilike.%$query%,bus_code.ilike.%$query%')
        .limit(8);

    final schoolResults = await supabase
        .from('schools')
        .select('id, name')
        .ilike('name', '%$query%')
        .limit(5);

    final combined = <Map<String, dynamic>>[
      for (final b in busResults) {...b, 'type': 'bus'},
      for (final s in schoolResults) {...s, 'type': 'school'},
    ];

    final liveBusIds = await _loadLiveBusIds(busResults);
    if (!mounted) return;
    setState(() {
      _suggestions = combined;
      _liveBusIds = liveBusIds;
      _searching = false;
    });
  }

  Future<void> _openBusesForSchool(String schoolId, String schoolName) async {
    final result = await supabase
        .from('buses')
        .select('id, bus_number, bus_code, schools(name)')
        .eq('school_id', schoolId)
        .order('bus_number');

    final liveBusIds = await _loadLiveBusIds(result);
    if (!mounted) return;

    if (result.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No buses found for $schoolName yet')),
      );
      return;
    }

    setState(() {
      _suggestions = [
        for (final b in result) {...b, 'type': 'bus'},
      ];
      _liveBusIds = liveBusIds;
    });
  }

  void _openBus(Map<String, dynamic> bus) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => StopsScreen(
          busId: bus['id'],
          busNumber: bus['bus_number'] ?? '',
          schoolName: bus['schools']?['name'] ?? '',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final showingSuggestions = _searchController.text.trim().isNotEmpty;

    return Scaffold(
      backgroundColor: BACKGROUND_BLUE,
      drawer: _buildDrawer(),
      appBar: AppBar(
        backgroundColor: PRIMARY_BLUE,
        foregroundColor: Colors.white,
        elevation: 8,
        title: const Text(
          'Find My Bus',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20),
        ),
      ),
      body: Column(
        children: [
          // Search bar
          Container(
            color: PRIMARY_BLUE,
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: PRIMARY_BLUE.withOpacity(0.15),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  )
                ],
              ),
              child: TextField(
                controller: _searchController,
                onChanged: _onSearchChanged,
                decoration: InputDecoration(
                  hintText: 'Bus No., school or college',
                  prefixIcon: const Icon(Icons.search, color: PRIMARY_BLUE),
                  suffixIcon: _searching
                      ? const Padding(
                          padding: EdgeInsets.all(12),
                          child: SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation(PRIMARY_BLUE)),
                          ),
                        )
                      : null,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ),
          ),

          if (!showingSuggestions)
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 10, 20, 2),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Search your bus number or school to see it live.',
                  style: TextStyle(fontSize: 13, color: Colors.blueGrey),
                ),
              ),
            ),

          Expanded(
            child: showingSuggestions
                ? _buildSuggestionsList()
                : _buildBrowseList(),
          ),

          // Bottom bar: Register Student | Driver Login
          _buildBottomBar(),
        ],
      ),
    );
  }

  Widget _buildSuggestionsList() {
    if (_suggestions.isEmpty && !_searching) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Text(
            'No buses or schools matched that search.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey),
          ),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: _suggestions.length,
      itemBuilder: (context, index) {
        final item = _suggestions[index];
        final isSchool = item['type'] == 'school';

        return ListTile(
          leading: CircleAvatar(
            backgroundColor: isSchool
                ? Colors.orange.shade50
                : LIGHT_BLUE,
            child: Icon(
              isSchool ? Icons.school : Icons.directions_bus,
              color: isSchool ? Colors.orange : PRIMARY_BLUE,
            ),
          ),
          title: Text(
            isSchool ? item['name'] : (item['bus_number'] ?? ''),
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          subtitle: Text(
            isSchool
                ? 'School — tap to see its buses'
                : (item['schools']?['name'] ?? ''),
          ),
          trailing: isSchool
              ? const Icon(Icons.chevron_right, color: Colors.grey)
              : _BusListTrailing(isLive: _liveBusIds.contains(item['id'])),
          onTap: () {
            if (isSchool) {
              _openBusesForSchool(item['id'], item['name']);
            } else {
              _openBus(item);
            }
          },
        );
      },
    );
  }

  Widget _buildBrowseList() {
    if (_loadingBrowse) {
      return const Center(child: CircularProgressIndicator(valueColor: AlwaysStoppedAnimation(PRIMARY_BLUE)));
    }
    if (_browseBuses.isEmpty) {
      return const Center(
        child: Text('No buses registered yet', style: TextStyle(color: Colors.grey)),
      );
    }

    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: Text(
            'BROWSE BUSES',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: Colors.grey,
              letterSpacing: 0.5,
            ),
          ),
        ),
        for (final bus in _browseBuses)
          ListTile(
            leading: CircleAvatar(
              backgroundColor: LIGHT_BLUE,
              child: const Icon(Icons.directions_bus, color: PRIMARY_BLUE),
            ),
            title: Text(
              bus['bus_number'] ?? '',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            subtitle: Text(bus['schools']?['name'] ?? ''),
            trailing: _BusListTrailing(isLive: _liveBusIds.contains(bus['id'])),
            onTap: () => _openBus(bus),
          ),
      ],
    );
  }

  Widget _buildBottomBar() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.14),
            blurRadius: 14,
            offset: const Offset(0, -3),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
          Expanded(
              child: _BottomBarButton(
                icon: Icons.admin_panel_settings_outlined,
                label: 'Admin Login',
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const AdminLoginScreen()),
                  );
                },
              ),
            ),
            Container(width: 1, height: 40, color: Colors.grey.shade200),
            Expanded(
              child: _BottomBarButton(
                icon: Icons.badge_outlined,
                label: 'Driver Login',
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const LoginScreen()),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDrawer() {
    return Drawer(
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [PRIMARY_BLUE, SECONDARY_BLUE],
              ),
            ),
            child: DrawerHeader(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Find My Bus',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 26,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Text(
                    'Find My Bus - Easy Tracking',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ),

          // 📞 SUPPORT SECTION
          const SizedBox.shrink(),
          /*Container(
            padding: const EdgeInsets.all(16),
            margin: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: LIGHT_BLUE,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: PRIMARY_BLUE, width: 1.5),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '📞 Support',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: PRIMARY_BLUE,
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    const Icon(Icons.phone, color: PRIMARY_BLUE, size: 16),
                    const SizedBox(width: 8),
                    Expanded(
                      child: GestureDetector(
                        onTap: () {
                          // Open phone dialer
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Call: +91 6369669753')),
                          );
                        },
                        child: const Text(
                          '+91 6369669753',
                          style: TextStyle(
                            fontSize: 12,
                            color: PRIMARY_BLUE,
                            fontWeight: FontWeight.w600,
                            decoration: TextDecoration.underline,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Icon(Icons.email, color: PRIMARY_BLUE, size: 16),
                    const SizedBox(width: 8),
                    Expanded(
                      child: GestureDetector(
                        onTap: () {
                          // Open email
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Email: gokulm4a1@gmail.com')),
                          );
                        },
                        child: const Text(
                          'gokulm4a1@gmail.com',
                          style: TextStyle(
                            fontSize: 12,
                            color: PRIMARY_BLUE,
                            fontWeight: FontWeight.w600,
                            decoration: TextDecoration.underline,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),*/

          const SizedBox(height: 8),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              'MENU',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: Colors.grey,
                letterSpacing: 0.5,
              ),
            ),
          ),
          const SizedBox(height: 8),

          // 🎨 Theme & Settings
          _DrawerItem(
            icon: Icons.person_outline,
            label: 'My Profile',
            onTap: () {
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Profile - Coming Soon')),
              );
            },
          ),

          // 🌐 Language
          _DrawerItem(
            icon: Icons.language,
            label: 'Language',
            onTap: () {
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Language Settings - Coming Soon')),
              );
            },
          ),

          // 👤 Profile
          _DrawerItem(
            icon: Icons.help_outline,
            label: 'FAQ & Help',
            onTap: () {
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('FAQ - Coming Soon')),
              );
            },
          ),

          // ⭐ Rate Us
          _DrawerItem(
            icon: Icons.lightbulb_outline,
            label: 'Suggest a Feature',
            onTap: () {
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Feature Request - Coming Soon')),
              );
            },
          ),

          // ❓ FAQ
          _DrawerItem(
            icon: Icons.info_outline,
            label: 'About Find My Bus',
            onTap: () {
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('About - v1.0.0')),
              );
            },
          ),

          // 💡 Suggest Feature
          _DrawerItem(
            icon: Icons.share_outlined,
            label: 'Share App',
            onTap: () {
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Share - Coming Soon')),
              );
            },
          ),

          // 📋 About
          _DrawerItem(
            icon: Icons.security_outlined,
            label: 'Privacy Policy',
            onTap: () {
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Privacy Policy - Coming Soon')),
              );
            },
          ),

          // 📤 Share App
          _DrawerItem(
            icon: Icons.palette_outlined,
            label: 'Theme & Settings',
            onTap: () {
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Theme Settings - Coming Soon')),
              );
            },
          ),

          // 🔒 Privacy Policy
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Divider(),
          ),

          // Driver Login
          ListTile(
            leading: const Icon(Icons.badge_outlined, color: PRIMARY_BLUE),
            title: const Text(
              'Driver Login',
              style: TextStyle(fontWeight: FontWeight.w600, color: PRIMARY_BLUE),
            ),
            onTap: () {
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const LoginScreen()),
              );
            },
          ),
          _buildSupportCard(),
        ],
      ),
    );
  }

  Widget _buildSupportCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      margin: const EdgeInsets.fromLTRB(12, 4, 12, 16),
      decoration: BoxDecoration(
        color: LIGHT_BLUE,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: PRIMARY_BLUE, width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Support',
              style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: PRIMARY_BLUE)),
          const SizedBox(height: 10),
          Row(children: [
            const Icon(Icons.phone, color: PRIMARY_BLUE, size: 16),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: () => ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Call: +91 6369669753')),
              ),
              child: const Text('+91 6369669753',
                  style: TextStyle(
                      fontSize: 12,
                      color: PRIMARY_BLUE,
                      decoration: TextDecoration.underline)),
            ),
          ]),
          const SizedBox(height: 8),
          Row(children: [
            const Icon(Icons.email, color: PRIMARY_BLUE, size: 16),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: () => ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Email: gokulm4a1@gmail.com')),
              ),
              child: const Text('gokulm4a1@gmail.com',
                  style: TextStyle(
                      fontSize: 12,
                      color: PRIMARY_BLUE,
                      decoration: TextDecoration.underline)),
            ),
          ]),
        ],
      ),
    );
  }
}

class _DrawerItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _DrawerItem({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, color: PRIMARY_BLUE, size: 22),
      title: Text(
        label,
        style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 14),
      ),
      trailing: const Icon(Icons.chevron_right, color: Colors.grey, size: 18),
      onTap: onTap,
    );
  }
}

class _BusListTrailing extends StatelessWidget {
  final bool isLive;

  const _BusListTrailing({required this.isLive});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 9,
          height: 9,
          decoration: BoxDecoration(
            color: isLive ? Colors.green : Colors.grey.shade400,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 10),
        const Icon(Icons.chevron_right, color: Colors.grey),
      ],
    );
  }
}

class _BottomBarButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _BottomBarButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: PRIMARY_BLUE, size: 26),
            const SizedBox(height: 4),
            Text(
              label,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: PRIMARY_BLUE,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
