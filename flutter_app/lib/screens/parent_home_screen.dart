import 'dart:async';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'about_screen.dart';
import 'faq_screen.dart';
import 'login_screen.dart';
import 'privacy_screen.dart';
import 'profile_screen.dart';
import 'stops_screen.dart';
import 'suggest_feature_screen.dart';
import '../services/language_service.dart';
import '../services/notification_service.dart';
import '../services/session_store.dart';
import '../services/voice_assistant_service.dart';
import '../utils/time_utils.dart';

const Color PRIMARY_BLUE = Color(0xFF0052CC);
const Color SECONDARY_BLUE = Color(0xFF1E6BFF);
const Color LIGHT_BLUE = Color(0xFFE8F0FE);
const Color BACKGROUND_BLUE = Color(0xFFF7F9FC);

class ParentHomeScreen extends StatefulWidget {
  const ParentHomeScreen({super.key});

  @override
  State<ParentHomeScreen> createState() => _ParentHomeScreenState();
}

class _ParentHomeScreenState extends State<ParentHomeScreen> {
  final LanguageService _languageService = LanguageService();
  final Map<String, bool> _busLiveStatus = {};
  bool _notificationPermissionDenied = false;
  Timer? _liveCheckTimer;
  StreamSubscription? _fcmSub;

  @override
  void initState() {
    super.initState();
    _languageService.addListener(_onLanguageChanged);
    _checkPermissionStatus();
    _loadAllBusesLiveStatus();
    _liveCheckTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      _loadAllBusesLiveStatus();
    });

    _fcmSub = NotificationService().onForegroundMessage.listen((message) {
      if (!mounted) return;
      final title = message.notification?.title ?? 'Bus Update';
      final body = message.notification?.body ?? '';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.notifications_active, color: Colors.white),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
                    if (body.isNotEmpty) Text(body, style: const TextStyle(fontSize: 12)),
                  ],
                ),
              ),
            ],
          ),
          backgroundColor: PRIMARY_BLUE,
          duration: const Duration(seconds: 4),
          behavior: SnackBarBehavior.floating,
        ),
      );
      if (body.isNotEmpty) {
        VoiceAssistantService().speak(body);
      }
    });
  }

  @override
  void dispose() {
    _languageService.removeListener(_onLanguageChanged);
    _liveCheckTimer?.cancel();
    _fcmSub?.cancel();
    super.dispose();
  }

  void _onLanguageChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _checkPermissionStatus() async {
    try {
      final status = await Permission.notification.status;
      final prefs = await SharedPreferences.getInstance();
      final hasAsked = prefs.getBool('asked_notification_permission') ?? false;

      if (!mounted) return;

      if (status.isDenied || status.isPermanentlyDenied) {
        setState(() {
          _notificationPermissionDenied = true;
        });

        if (!hasAsked) {
          await prefs.setBool('asked_notification_permission', true);
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _showNotificationPermissionDialog();
          });
        }
      } else {
        setState(() {
          _notificationPermissionDenied = false;
        });
      }
    } catch (_) {}
  }

  Future<void> _requestNotificationPermission() async {
    try {
      final status = await Permission.notification.request();
      if (!mounted) return;
      setState(() {
        _notificationPermissionDenied = status.isDenied || status.isPermanentlyDenied;
      });
      if (status.isPermanentlyDenied) {
        await openAppSettings();
      }
    } catch (_) {}
  }

  void _showNotificationPermissionDialog() {
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            const Icon(Icons.notifications_active_rounded, color: PRIMARY_BLUE, size: 26),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                _languageService.getText('permission_dialog_title'),
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
            ),
          ],
        ),
        content: Text(
          _languageService.getText('permission_dialog_desc'),
          style: const TextStyle(fontSize: 13, color: Colors.blueGrey, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx),
            child: Text(
              _languageService.getText('not_now'),
              style: const TextStyle(color: Colors.grey),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: PRIMARY_BLUE,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () async {
              Navigator.pop(dialogCtx);
              await _requestNotificationPermission();
            },
            child: Text(_languageService.getText('allow_notifications')),
          ),
        ],
      ),
    );
  }

  Future<void> _loadAllBusesLiveStatus() async {
    if (!mounted) return;
    final session = context.read<SessionController>();
    final students = session.profile?.students ?? [];
    final api = session.apiClient;

    final busIds = students
        .map((s) => s.busId)
        .whereType<String>()
        .where((id) => id.isNotEmpty)
        .toSet();

    for (final busId in busIds) {
      try {
        final res = await api.get('/api/parent/bus/$busId/live');
        final isLive = res is Map ? isLiveTimestamp(res['timestamp']?.toString()) : false;
        if (mounted) {
          setState(() {
            _busLiveStatus[busId] = isLive;
          });
        }
      } catch (_) {}
    }
  }

  void _openStudentBus(StudentInfo student) {
    if (student.busId == null || student.busId!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_languageService.getText('bus_not_assigned')),
          backgroundColor: Colors.amber.shade900,
        ),
      );
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => StopsScreen(
          busId: student.busId!,
          busNumber: student.busNumber ?? '',
          schoolName: student.schoolName ?? '',
          studentStopId: student.stopId,
        ),
      ),
    );
  }

  void _showShareAppDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(_languageService.getText('share_app')),
        content: const Text(
          'Find My Bus — School bus live tracking app for parents.\n\nDownload and track your child safely!',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(_languageService.getText('close')),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionController>();
    final students = session.profile?.students ?? [];

    return Scaffold(
      backgroundColor: BACKGROUND_BLUE,
      drawer: _buildDrawer(context, session),
      appBar: AppBar(
        backgroundColor: PRIMARY_BLUE,
        foregroundColor: Colors.white,
        elevation: 4,
        title: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: Image.asset(
                'assets/icon/icon.png',
                width: 26,
                height: 26,
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => const Icon(
                  Icons.directions_bus_rounded,
                  color: Colors.white,
                  size: 24,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Text(
              _languageService.getText('app_title'),
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
            ),
          ],
        ),
        actions: [
          TextButton.icon(
            onPressed: () => _languageService.toggleLanguage(),
            icon: const Icon(Icons.language, color: Colors.white, size: 18),
            label: Text(
              _languageService.isTamil ? 'தமிழ்' : 'EN',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: RefreshIndicator(
        color: PRIMARY_BLUE,
        onRefresh: () async {
          await session.refresh();
          await _loadAllBusesLiveStatus();
        },
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          children: [
            // Notification Permission Banner
            if (_notificationPermissionDenied)
              Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.amber.shade100,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.amber.shade700),
                ),
                child: Row(
                  children: [
                    Icon(Icons.notifications_off_outlined, color: Colors.amber.shade900, size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _languageService.getText('permission_banner_msg'),
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.amber.shade900,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.amber.shade800,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        minimumSize: const Size(0, 32),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      onPressed: () => openAppSettings(),
                      child: Text(
                        _languageService.getText('open_settings'),
                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
              ),

            // Section Heading
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                _languageService.getText('parent_home_title'),
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: PRIMARY_BLUE,
                ),
              ),
            ),

            if (students.isEmpty)
              Container(
                padding: const EdgeInsets.all(24),
                margin: const EdgeInsets.only(top: 20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  children: [
                    const Icon(Icons.school_outlined, size: 48, color: Colors.grey),
                    const SizedBox(height: 12),
                    Text(
                      _languageService.getText('no_students_found'),
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.grey, fontSize: 14),
                    ),
                  ],
                ),
              )
            else
              ...students.map((student) => _buildStudentCard(student)),

            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _buildStudentCard(StudentInfo student) {
    final hasBus = student.busId != null && student.busId!.isNotEmpty;
    final hasStop = student.stopName != null && student.stopName!.isNotEmpty;
    final isLive = hasBus ? (_busLiveStatus[student.busId] ?? false) : false;

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => _openStudentBus(student),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Top Row: Logo, Name & Live status badge
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: Image.asset(
                        'assets/icon/icon.png',
                        width: 44,
                        height: 44,
                        fit: BoxFit.contain,
                        errorBuilder: (_, __, ___) => Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: LIGHT_BLUE,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(
                            Icons.directions_bus_rounded,
                            size: 28,
                            color: PRIMARY_BLUE,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            student.studentName?.isNotEmpty == true
                                ? student.studentName!
                                : (_languageService.isTamil ? 'மாணவர்' : 'Student'),
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF0F172A),
                            ),
                          ),
                          if (student.schoolName != null && student.schoolName!.isNotEmpty)
                            Text(
                              student.schoolName!,
                              style: const TextStyle(fontSize: 12, color: Colors.blueGrey),
                              overflow: TextOverflow.ellipsis,
                            ),
                        ],
                      ),
                    ),
                    if (hasBus)
                      _buildLiveBadge(isLive)
                  ],
                ),

                const SizedBox(height: 12),
                const Divider(height: 1),
                const SizedBox(height: 12),

                // Bus, Stop and Time Details
                if (hasBus && hasStop) ...[
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: LIGHT_BLUE,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          'Bus ${student.busNumber ?? ''}',
                          style: const TextStyle(
                            color: PRIMARY_BLUE,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Row(
                          children: [
                            const Icon(Icons.location_on_outlined, size: 16, color: PRIMARY_BLUE),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                student.stopName!,
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  if (student.stopExpectedTime != null && student.stopExpectedTime!.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        const Icon(Icons.schedule_outlined, size: 14, color: Colors.grey),
                        const SizedBox(width: 6),
                        Text(
                          '${_languageService.getText('expected_time')}: ${student.stopExpectedTime}',
                          style: const TextStyle(fontSize: 12, color: Colors.blueGrey),
                        ),
                        const Spacer(),
                        const Text(
                          'Track >',
                          style: TextStyle(
                            color: PRIMARY_BLUE,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ],
                ] else
                  Text(
                    _languageService.getText('bus_not_assigned'),
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.amber.shade900,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLiveBadge(bool isLive) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: isLive ? Colors.green.shade50 : Colors.grey.shade100,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isLive ? Colors.green.shade600 : Colors.grey.shade400,
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.circle,
            size: 8,
            color: isLive ? Colors.green.shade600 : Colors.grey.shade500,
          ),
          const SizedBox(width: 4),
          Text(
            isLive ? _languageService.getText('live') : _languageService.getText('offline'),
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: isLive ? Colors.green.shade800 : Colors.grey.shade700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDrawer(BuildContext context, SessionController session) {
    final profile = session.profile;
    final parentPhone = profile?.phone ?? '';

    return Drawer(
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(16, 44, 16, 20),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [PRIMARY_BLUE, SECONDARY_BLUE],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.asset(
                    'assets/icon/icon.png',
                    width: 48,
                    height: 48,
                    fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) => const Icon(
                      Icons.directions_bus_rounded,
                      color: Colors.white,
                      size: 40,
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _languageService.getText('app_title'),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      if (parentPhone.isNotEmpty)
                        Text(
                          parentPhone,
                          style: const TextStyle(color: Colors.white70, fontSize: 12),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 8),

          // Profile
          ListTile(
            leading: const Icon(Icons.person_outline, color: PRIMARY_BLUE),
            title: Text(_languageService.getText('my_profile')),
            onTap: () {
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const ProfileScreen()),
              );
            },
          ),

          // Language Toggle
          ListTile(
            leading: const Icon(Icons.language, color: PRIMARY_BLUE),
            title: Text(_languageService.getText('language')),
            trailing: Text(
              _languageService.isTamil ? 'தமிழ்' : 'English',
              style: const TextStyle(fontWeight: FontWeight.bold, color: PRIMARY_BLUE),
            ),
            onTap: () {
              _languageService.toggleLanguage();
            },
          ),

          // FAQ
          ListTile(
            leading: const Icon(Icons.help_outline, color: PRIMARY_BLUE),
            title: Text(_languageService.getText('faq_help')),
            onTap: () {
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const FAQScreen()),
              );
            },
          ),

          // Suggest Feature
          ListTile(
            leading: const Icon(Icons.lightbulb_outline, color: PRIMARY_BLUE),
            title: Text(_languageService.getText('suggest_feature')),
            onTap: () {
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const SuggestFeatureScreen()),
              );
            },
          ),

          // About
          ListTile(
            leading: const Icon(Icons.info_outline, color: PRIMARY_BLUE),
            title: Text(_languageService.getText('about_app')),
            onTap: () {
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const AboutScreen()),
              );
            },
          ),

          // Share
          ListTile(
            leading: const Icon(Icons.share_outlined, color: PRIMARY_BLUE),
            title: Text(_languageService.getText('share_app')),
            onTap: () {
              Navigator.pop(context);
              _showShareAppDialog();
            },
          ),

          // Privacy Policy
          ListTile(
            leading: const Icon(Icons.security_outlined, color: PRIMARY_BLUE),
            title: Text(_languageService.getText('privacy_policy')),
            onTap: () {
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const PrivacyScreen()),
              );
            },
          ),

          const Divider(),

          // Driver Login
          ListTile(
            leading: const Icon(Icons.badge_outlined, color: PRIMARY_BLUE),
            title: Text(
              _languageService.getText('driver_login'),
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

          // Log Out
          ListTile(
            leading: const Icon(Icons.logout, color: Colors.red),
            title: Text(
              _languageService.getText('logout'),
              style: const TextStyle(color: Colors.red, fontWeight: FontWeight.w600),
            ),
            onTap: () {
              Navigator.pop(context);
              session.logout();
            },
          ),
        ],
      ),
    );
  }
}
