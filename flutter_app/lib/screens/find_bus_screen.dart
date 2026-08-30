import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'login_screen.dart';
import 'stops_screen.dart';
import 'admin_login_screen.dart';
import 'profile_screen.dart';
import 'faq_screen.dart';
import 'suggest_feature_screen.dart';
import 'about_screen.dart';
import 'privacy_screen.dart';
import 'settings_screen.dart';
import '../services/language_service.dart';

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
  final languageService = LanguageService();
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
    _debounce = Timer(const Duration(milliseconds: 300), () {
      _runSearch(query.trim());
    });
  }

  Future<void> _runSearch(String query) async {
    setState(() => _searching = true);

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
    return ListenableBuilder(
      listenable: languageService,
      builder: (context, _) {
        final showingSuggestions = _searchController.text.trim().isNotEmpty;

        return Scaffold(
          backgroundColor: BACKGROUND_BLUE,
          drawer: _buildDrawer(),
          appBar: AppBar(
            backgroundColor: PRIMARY_BLUE,
            foregroundColor: Colors.white,
            elevation: 8,
            title: Text(
              languageService.getText('app_title'),
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 19),
            ),
            actions: [
              IconButton(
                tooltip: languageService.getText('language'),
                icon: const Icon(Icons.language_rounded),
                onPressed: _showLanguageDialog,
              ),
            ],
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
                      hintText: languageService.getText('search_hint'),
                      prefixIcon: const Icon(Icons.search, color: PRIMARY_BLUE),
                      suffixIcon: _searching
                          ? const Padding(
                              padding: EdgeInsets.all(12),
                              child: SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation(PRIMARY_BLUE),
                                ),
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
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 10, 20, 2),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      languageService.getText('search_subtext'),
                      style: const TextStyle(fontSize: 13, color: Colors.blueGrey),
                    ),
                  ),
                ),

              Expanded(
                child: showingSuggestions
                    ? _buildSuggestionsList()
                    : _buildBrowseList(),
              ),

              _buildBottomBar(),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSuggestionsList() {
    if (_suggestions.isEmpty && !_searching) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(
            languageService.getText('no_search_results'),
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.grey),
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
            backgroundColor: isSchool ? Colors.orange.shade50 : LIGHT_BLUE,
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
                ? languageService.getText('tap_to_see_buses')
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
      return const Center(
        child: CircularProgressIndicator(
          valueColor: AlwaysStoppedAnimation(PRIMARY_BLUE),
        ),
      );
    }
    if (_browseBuses.isEmpty) {
      return Center(
        child: Text(
          languageService.getText('no_buses'),
          style: const TextStyle(color: Colors.grey),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: Text(
            languageService.getText('browse_buses'),
            style: const TextStyle(
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
                label: languageService.getText('admin_login'),
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
                label: languageService.getText('driver_login'),
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
                  Text(
                    languageService.getText('app_title'),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    languageService.getText('app_subtitle'),
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              languageService.getText('menu'),
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: Colors.grey,
                letterSpacing: 0.5,
              ),
            ),
          ),
          const SizedBox(height: 8),

          // 👤 My Profile
          _DrawerItem(
            icon: Icons.person_outline,
            label: languageService.getText('my_profile'),
            onTap: () {
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const ProfileScreen()),
              );
            },
          ),

          // 🌐 Language Selection (English & Tamil)
          _DrawerItem(
            icon: Icons.language,
            label: languageService.getText('language'),
            trailingText: languageService.isTamil ? 'தமிழ்' : 'English',
            onTap: () {
              Navigator.pop(context);
              _showLanguageDialog();
            },
          ),

          // ❓ FAQ & Help
          _DrawerItem(
            icon: Icons.help_outline,
            label: languageService.getText('faq_help'),
            onTap: () {
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const FAQScreen()),
              );
            },
          ),

          // 💡 Suggest Feature
          _DrawerItem(
            icon: Icons.lightbulb_outline,
            label: languageService.getText('suggest_feature'),
            onTap: () {
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const SuggestFeatureScreen()),
              );
            },
          ),

          // ℹ️ About
          _DrawerItem(
            icon: Icons.info_outline,
            label: languageService.getText('about_app'),
            onTap: () {
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const AboutScreen()),
              );
            },
          ),

          // 📤 Share App
          _DrawerItem(
            icon: Icons.share_outlined,
            label: languageService.getText('share_app'),
            onTap: () {
              Navigator.pop(context);
              _showShareAppDialog();
            },
          ),

          // 🔒 Privacy Policy
          _DrawerItem(
            icon: Icons.security_outlined,
            label: languageService.getText('privacy_policy'),
            onTap: () {
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const PrivacyScreen()),
              );
            },
          ),

          // 🎨 Theme & Settings
          _DrawerItem(
            icon: Icons.palette_outlined,
            label: languageService.getText('theme_settings'),
            onTap: () {
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const SettingsScreen()),
              );
            },
          ),

          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Divider(),
          ),

          // Driver Login
          ListTile(
            leading: const Icon(Icons.badge_outlined, color: PRIMARY_BLUE),
            title: Text(
              languageService.getText('driver_login'),
              style: const TextStyle(fontWeight: FontWeight.w600, color: PRIMARY_BLUE),
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
          Text(
            languageService.getText('support'),
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: PRIMARY_BLUE,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              const Icon(Icons.phone, color: PRIMARY_BLUE, size: 16),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: () => ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Call: +91 6369669753')),
                ),
                child: const Text(
                  '+91 6369669753',
                  style: TextStyle(
                    fontSize: 12,
                    color: PRIMARY_BLUE,
                    decoration: TextDecoration.underline,
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
              GestureDetector(
                onTap: () => ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Email: gokulm4a1@gmail.com')),
                ),
                child: const Text(
                  'gokulm4a1@gmail.com',
                  style: TextStyle(
                    fontSize: 12,
                    color: PRIMARY_BLUE,
                    decoration: TextDecoration.underline,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // 🌐 LANGUAGE SELECTION DIALOG (English & Tamil)
  void _showLanguageDialog() {
    showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: Row(
              children: [
                const Icon(Icons.language_rounded, color: PRIMARY_BLUE),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    languageService.getText('select_language'),
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                RadioListTile<String>(
                  value: 'en',
                  groupValue: languageService.currentLanguage,
                  title: const Text('English', style: TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: const Text('Default system language'),
                  activeColor: PRIMARY_BLUE,
                  onChanged: (val) {
                    if (val != null) {
                      languageService.setLanguage(val);
                      setDialogState(() {});
                      Navigator.pop(context);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Language set to English')),
                      );
                    }
                  },
                ),
                const Divider(),
                RadioListTile<String>(
                  value: 'ta',
                  groupValue: languageService.currentLanguage,
                  title: const Text('தமிழ் (Tamil)', style: TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: const Text('தமிழ் மொழி வடிவம்'),
                  activeColor: PRIMARY_BLUE,
                  onChanged: (val) {
                    if (val != null) {
                      languageService.setLanguage(val);
                      setDialogState(() {});
                      Navigator.pop(context);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('மொழி தமிழில் மாற்றப்பட்டது (Language set to Tamil)')),
                      );
                    }
                  },
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(languageService.getText('close')),
              ),
            ],
          );
        },
      ),
    );
  }

  // 📤 SHARE APP DIALOG
  void _showShareAppDialog() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            const Icon(Icons.share_outlined, color: PRIMARY_BLUE),
            const SizedBox(width: 8),
            Text(languageService.getText('share_app')),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.qr_code_2_rounded, size: 80, color: PRIMARY_BLUE),
            const SizedBox(height: 12),
            Text(
              languageService.isTamil
                  ? 'பள்ளி மற்றும் பெற்றோருக்கு செயலியைப் பகிரவும்'
                  : 'Share Find My Bus App link with parents & drivers',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12, color: Colors.blueGrey),
            ),
            const SizedBox(height: 12),
            SelectableText(
              'https://trackbus.school/download',
              style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blue.shade800),
            ),
          ],
        ),
        actions: [
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(backgroundColor: PRIMARY_BLUE, foregroundColor: Colors.white),
            icon: const Icon(Icons.copy, size: 16),
            label: const Text('Copy Link'),
            onPressed: () {
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('App link copied to clipboard!')),
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
  final String? trailingText;
  final VoidCallback onTap;

  const _DrawerItem({
    required this.icon,
    required this.label,
    this.trailingText,
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
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (trailingText != null)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: Text(
                trailingText!,
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: PRIMARY_BLUE),
              ),
            ),
          const Icon(Icons.chevron_right, color: Colors.grey, size: 18),
        ],
      ),
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
