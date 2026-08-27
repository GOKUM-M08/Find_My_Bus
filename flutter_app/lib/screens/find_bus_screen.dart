import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'login_screen.dart';
import 'stops_screen.dart';

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

    setState(() {
      _browseBuses = List<Map<String, dynamic>>.from(result);
      _loadingBrowse = false;
    });
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

    if (!mounted) return;
    setState(() {
      _suggestions = combined;
      _searching = false;
    });
  }

  Future<void> _openBusesForSchool(String schoolId, String schoolName) async {
    final result = await supabase
        .from('buses')
        .select('id, bus_number, bus_code, schools(name)')
        .eq('school_id', schoolId)
        .order('bus_number');

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
      backgroundColor: const Color(0xFFF3F5F9),
      drawer: _buildDrawer(),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E6BFF),
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text(
          'Find My Bus',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
      body: Column(
        children: [
          // Search bar
          Container(
            color: const Color(0xFF1E6BFF),
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
              ),
              child: TextField(
                controller: _searchController,
                onChanged: _onSearchChanged,
                decoration: InputDecoration(
                  hintText: 'Bus No., school or college',
                  prefixIcon: const Icon(Icons.search, color: Color(0xFF1E6BFF)),
                  suffixIcon: _searching
                      ? const Padding(
                          padding: EdgeInsets.all(12),
                          child: SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
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
                : const Color(0xFF1E6BFF).withOpacity(0.1),
            child: Icon(
              isSchool ? Icons.school : Icons.directions_bus,
              color: isSchool ? Colors.orange : const Color(0xFF1E6BFF),
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
          trailing: const Icon(Icons.chevron_right, color: Colors.grey),
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
      return const Center(child: CircularProgressIndicator());
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
              backgroundColor: const Color(0xFF1E6BFF).withOpacity(0.1),
              child: const Icon(Icons.directions_bus, color: Color(0xFF1E6BFF)),
            ),
            title: Text(
              bus['bus_number'] ?? '',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            subtitle: Text(bus['schools']?['name'] ?? ''),
            trailing: const Icon(Icons.chevron_right, color: Colors.grey),
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
            color: Colors.black.withOpacity(0.06),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            Expanded(
              child: _BottomBarButton(
                icon: Icons.person_add_alt,
                label: 'Register Student',
                onTap: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'Ask your school admin to register your child\'s bus.',
                      ),
                    ),
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
          const DrawerHeader(
            decoration: BoxDecoration(color: Color(0xFF1E6BFF)),
            child: Align(
              alignment: Alignment.bottomLeft,
              child: Text(
                'Find My Bus',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          const _DrawerItem(icon: Icons.language, label: 'Language'),
          const _DrawerItem(icon: Icons.person_outline, label: 'Profile'),
          const _DrawerItem(icon: Icons.star_border, label: 'Rate us'),
          const _DrawerItem(icon: Icons.support_agent, label: 'Support'),
          const _DrawerItem(icon: Icons.lightbulb_outline, label: 'Suggest a feature'),
          const _DrawerItem(icon: Icons.help_outline, label: 'How to use'),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.badge_outlined),
            title: const Text('Driver Login'),
            onTap: () {
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const LoginScreen()),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _DrawerItem extends StatelessWidget {
  final IconData icon;
  final String label;

  const _DrawerItem({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, color: Colors.grey.shade700),
      title: Text(label),
      onTap: () {
        Navigator.pop(context);
        // NOTE: these drawer items are placeholders — Language,
        // Profile, Rate us, Support, Suggest a feature, and How to
        // use weren't specified beyond the wireframe, so they're
        // stubbed here ready to wire up to real screens later.
      },
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
            Icon(icon, color: const Color(0xFF1E6BFF), size: 22),
            const SizedBox(height: 4),
            Text(
              label,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Color(0xFF1E6BFF),
              ),
            ),
          ],
        ),
      ),
    );
  }
}