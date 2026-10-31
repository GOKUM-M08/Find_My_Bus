import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../services/language_service.dart';
import '../services/notification_prefs.dart';

class NotificationSettingsScreen extends StatefulWidget {
  const NotificationSettingsScreen({super.key});

  @override
  State<NotificationSettingsScreen> createState() =>
      _NotificationSettingsScreenState();
}

class _NotificationSettingsScreenState
    extends State<NotificationSettingsScreen> with WidgetsBindingObserver {
  static const Color primaryBlue = Color(0xFF1E3A8A);
  static const Color secondaryBlue = Color(0xFF3B82F6);
  static const Color backgroundLight = Color(0xFFF8FAFC);

  final NotificationPrefs _prefs = NotificationPrefs();
  final LanguageService _lang = LanguageService();

  PermissionStatus? _permissionStatus;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _prefs.init();
    _checkPermission();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkPermission();
    }
  }

  Future<void> _checkPermission() async {
    try {
      final status = await Permission.notification.status;
      if (mounted) {
        setState(() {
          _permissionStatus = status;
        });
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final isTa = _lang.isTamil;

    return Scaffold(
      backgroundColor: backgroundLight,
      appBar: AppBar(
        title: Text(
          isTa ? 'அறிவிப்பு அமைப்புகள்' : 'Notification Settings',
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
        ),
        backgroundColor: primaryBlue,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: AnimatedBuilder(
        animation: _prefs,
        builder: (context, _) {
          return ListView(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
            children: [
              _buildHeaderBanner(isTa),
              const SizedBox(height: 16),
              _buildMasterToggleCard(isTa),
              const SizedBox(height: 16),
              _buildLanguageChoiceCard(isTa),
              const SizedBox(height: 16),
              _buildPermissionStatusCard(isTa),
              const SizedBox(height: 16),
              _buildBatteryOptimizationCard(isTa),
            ],
          );
        },
      ),
    );
  }

  Widget _buildHeaderBanner(bool isTa) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [primaryBlue, secondaryBlue],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: primaryBlue.withAlpha(50),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.asset(
              'assets/icon/icon.png',
              width: 52,
              height: 52,
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) => const Icon(
                Icons.notifications_active_rounded,
                color: Colors.white,
                size: 40,
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isTa ? 'குரல் அடிப்படையிலான அறிவிப்புகள்' : 'Voice-Based Bus Alerts',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  isTa
                      ? 'போன் லாக் செய்யப்பட்டிருந்தாலும் குரல் அறிவிப்புகள் கேட்கும்.'
                      : 'Audio alerts play even when phone is locked and screen is off.',
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMasterToggleCard(bool isTa) {
    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
        child: SwitchListTile(
          value: _prefs.enabled,
          activeThumbColor: primaryBlue,
          title: Text(
            isTa ? 'பேருந்து அறிவிப்புகள்' : 'Bus alerts',
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
          subtitle: Text(
            isTa
                ? 'பேருந்து புறப்படும்போது, அருகில் வரும்போது மற்றும் கல்லூரி அடையும்போது அறிவிப்புகளைப் பெறவும்.'
                : 'Receive alerts when bus leaves first stop, is 2 stops away, and reaches college.',
            style: const TextStyle(fontSize: 12, color: Colors.black54),
          ),
          onChanged: (val) {
            _prefs.setEnabled(val);
          },
        ),
      ),
    );
  }

  Widget _buildLanguageChoiceCard(bool isTa) {
    final enabled = _prefs.enabled;

    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.language_rounded, color: primaryBlue, size: 20),
                const SizedBox(width: 8),
                Text(
                  isTa ? 'அறிவிப்பு மொழி' : 'Notification Language',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              isTa
                  ? 'அறிவிப்புகள் வரும்போது நீங்கள் தேர்வு செய்யும் மொழியில் குரல் ஒலிக்கும்.'
                  : 'Voice clips and text notifications will be delivered in this language.',
              style: const TextStyle(fontSize: 12, color: Colors.black54),
            ),
            const Divider(height: 24),
            RadioListTile<String>(
              value: 'ta',
              groupValue: _prefs.language,
              activeColor: primaryBlue,
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: const Text(
                'தமிழ் (Tamil)',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
              ),
              subtitle: const Text(
                'பேருந்து புறப்பட்டது, அருகில் வருகிறது, கல்லூரி அடைந்தது',
                style: TextStyle(fontSize: 11, color: Colors.black54),
              ),
              onChanged: enabled ? (val) => _prefs.setLanguage(val!) : null,
            ),
            RadioListTile<String>(
              value: 'en',
              groupValue: _prefs.language,
              activeColor: primaryBlue,
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: const Text(
                'English',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
              ),
              subtitle: const Text(
                'Bus started, 2 stops away, reached college',
                style: TextStyle(fontSize: 11, color: Colors.black54),
              ),
              onChanged: enabled ? (val) => _prefs.setLanguage(val!) : null,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPermissionStatusCard(bool isTa) {
    final isGranted = _permissionStatus?.isGranted == true;

    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  isGranted
                      ? Icons.check_circle_rounded
                      : Icons.warning_amber_rounded,
                  color: isGranted ? Colors.green : Colors.amber.shade800,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Text(
                  isTa ? 'போன் அறிவிப்பு அனுமதி' : 'Phone Permission Status',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              isGranted
                  ? (isTa
                      ? 'அறிவிப்புகள் போனில் அனுமதிக்கப்பட்டுள்ளன.'
                      : 'Notifications are allowed on this device.')
                  : (isTa
                      ? 'போன் செட்டிங்ஸில் அறிவிப்புகள் முடக்கப்பட்டுள்ளன. அறிவிப்புகளைப் பெற அனுமதியை இயக்கவும்.'
                      : 'Notifications are blocked in your phone settings. Enable them to receive bus alerts.'),
              style: TextStyle(
                fontSize: 12,
                color: isGranted ? Colors.black87 : Colors.red.shade700,
                fontWeight: isGranted ? FontWeight.normal : FontWeight.w600,
              ),
            ),
            if (!isGranted) ...[
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () => openAppSettings(),
                style: OutlinedButton.styleFrom(
                  foregroundColor: primaryBlue,
                  side: const BorderSide(color: primaryBlue),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                icon: const Icon(Icons.settings_outlined, size: 18),
                label: Text(
                  isTa ? 'போன் அமைப்புகளைத் திறக்க' : 'Open Phone Notification Settings',
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildBatteryOptimizationCard(bool isTa) {
    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.battery_charging_full_rounded,
                  color: primaryBlue,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Text(
                  isTa ? 'பேட்டரி அமைப்பு குறிப்பு' : 'Lock Screen Reliability Tip',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              isTa
                  ? 'போன் லாக் செய்யப்பட்டிருக்கும் போது குரல் அறிவிப்புகள் தடையின்றி ஒலிக்க, போன் அமைப்புகளில் "Find My Bus" செயலியை "Unrestricted" பேட்டரி அமைப்பில் வைக்கவும்.'
                  : 'To ensure alerts arrive instantly when your phone is locked or on battery saver, set battery usage for "Find My Bus" to "Unrestricted" in phone settings.',
              style: const TextStyle(fontSize: 12, color: Colors.black87, height: 1.4),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () => openAppSettings(),
              style: OutlinedButton.styleFrom(
                foregroundColor: primaryBlue,
                side: const BorderSide(color: primaryBlue),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              icon: const Icon(Icons.battery_saver_rounded, size: 18),
              label: Text(
                isTa ? 'செயலி அமைப்புகளைத் திறக்க' : 'Open App Info / Battery Settings',
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
