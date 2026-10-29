import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/language_service.dart';
import '../services/session_store.dart';

const Color PRIMARY_BLUE = Color(0xFF0052CC);
const Color SECONDARY_BLUE = Color(0xFF1E6BFF);
const Color LIGHT_BLUE = Color(0xFFE8F0FE);
const Color BACKGROUND_BLUE = Color(0xFFF7F9FC);

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final languageService = LanguageService();

  String _formatPhoneNumber(String? raw) {
    if (raw == null || raw.isEmpty) return '';
    final digits = raw.replaceAll(RegExp(r'\D'), '');
    if (digits.length == 10) {
      return '+91 ${digits.substring(0, 5)} ${digits.substring(5)}';
    } else if (digits.length == 12 && digits.startsWith('91')) {
      final local = digits.substring(2);
      return '+91 ${local.substring(0, 5)} ${local.substring(5)}';
    }
    return raw;
  }

  Future<void> _callHelpdesk(String phone) async {
    final clean = phone.replaceAll(RegExp(r'[^0-9+]'), '');
    final uri = Uri.parse('tel:$clean');
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri);
      } else {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Cannot launch dialer for $clean')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not open dialer: $e')),
      );
    }
  }

  void _showLogoutDialog(BuildContext context) {
    final isTa = languageService.isTamil;
    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: Text(isTa ? 'வெளியேறு' : 'Log Out'),
        content: Text(
          isTa
              ? 'நிச்சயமாக உங்கள் கணக்கிலிருந்து வெளியேற விரும்புகிறீர்களா?'
              : 'Are you sure you want to log out of your account?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx),
            child: Text(isTa ? 'ரத்து' : 'Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red.shade700,
              foregroundColor: Colors.white,
            ),
            onPressed: () {
              Navigator.pop(dialogCtx);
              Navigator.pop(context); // pop ProfileScreen
              context.read<SessionController>().logout();
            },
            child: Text(isTa ? 'வெளியேறு' : 'Log Out'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionController>();
    final profile = session.profile;
    final students = profile?.students ?? [];

    String parentName = '';
    for (final s in students) {
      if (s.parentName != null && s.parentName!.trim().isNotEmpty) {
        parentName = s.parentName!.trim();
        break;
      }
    }

    String? schoolPhone;
    String? schoolName;
    for (final s in students) {
      if (s.schoolPhone != null && s.schoolPhone!.trim().isNotEmpty) {
        schoolPhone = s.schoolPhone!.trim();
        schoolName = s.schoolName;
        break;
      }
    }

    final formattedPhone = _formatPhoneNumber(profile?.phone);

    return ListenableBuilder(
      listenable: languageService,
      builder: (context, _) {
        final isTa = languageService.isTamil;

        return Scaffold(
          backgroundColor: BACKGROUND_BLUE,
          appBar: AppBar(
            backgroundColor: PRIMARY_BLUE,
            foregroundColor: Colors.white,
            elevation: 4,
            title: Text(
              languageService.getText('my_profile'),
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
            ),
          ),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // Parent Card
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [PRIMARY_BLUE, SECONDARY_BLUE],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: PRIMARY_BLUE.withValues(alpha: 0.25),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(3),
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                      ),
                      child: const CircleAvatar(
                        radius: 30,
                        backgroundColor: LIGHT_BLUE,
                        child: Icon(Icons.person_rounded, size: 38, color: PRIMARY_BLUE),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            parentName.isNotEmpty ? parentName : (isTa ? 'பெற்றோர்' : 'Parent'),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          if (formattedPhone.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text(
                              formattedPhone,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                          const SizedBox(height: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.verified_user_rounded, size: 14, color: Colors.white),
                                const SizedBox(width: 4),
                                Text(
                                  isTa ? 'செயலிலுள்ளது' : 'Active Account',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // Students Section
              _buildSectionTitle(isTa ? 'குழந்தைகள்' : 'Students'),
              const SizedBox(height: 10),

              if (students.isEmpty)
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Text(
                    languageService.getText('no_students_found'),
                    style: const TextStyle(color: Colors.grey, fontSize: 13),
                  ),
                )
              else
                ...students.map((student) => _buildStudentCard(student, isTa)),

              const SizedBox(height: 24),

              // School Transport Helpdesk (Only shown if school phone is present)
              if (schoolPhone != null && schoolPhone.isNotEmpty) ...[
                _buildSectionTitle(languageService.getText('school_helpdesk')),
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: PRIMARY_BLUE.withValues(alpha: 0.2)),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.02),
                        blurRadius: 6,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.support_agent_rounded, color: PRIMARY_BLUE, size: 22),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              schoolName ?? (isTa ? 'பள்ளி உதவி மையம்' : 'School Helpdesk'),
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        languageService.getText('helpdesk_desc'),
                        style: const TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                      const Divider(height: 20),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            _formatPhoneNumber(schoolPhone),
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              color: PRIMARY_BLUE,
                              fontSize: 14,
                            ),
                          ),
                          ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: PRIMARY_BLUE,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                            ),
                            onPressed: () => _callHelpdesk(schoolPhone!),
                            icon: const Icon(Icons.call, size: 16),
                            label: Text(languageService.getText('call_school')),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
              ],

              // Logout Action
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.red.shade700,
                    side: BorderSide(color: Colors.red.shade300),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: () => _showLogoutDialog(context),
                  icon: const Icon(Icons.logout_rounded, size: 18),
                  label: Text(
                    languageService.getText('logout'),
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ),
              const SizedBox(height: 24),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: const TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.bold,
        color: PRIMARY_BLUE,
        letterSpacing: 0.3,
      ),
    );
  }

  Widget _buildStudentCard(StudentInfo student, bool isTa) {
    final hasBus = student.busNumber != null && student.busNumber!.isNotEmpty;
    final hasStop = student.stopName != null && student.stopName!.isNotEmpty;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // Logo badge instead of bus icon
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.asset(
                  'assets/icon/icon.png',
                  width: 36,
                  height: 36,
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) => const Icon(
                    Icons.directions_bus_rounded,
                    size: 32,
                    color: PRIMARY_BLUE,
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
                          : (isTa ? 'மாணவர்' : 'Student'),
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                    if (student.schoolName != null && student.schoolName!.isNotEmpty)
                      Text(
                        student.schoolName!,
                        style: const TextStyle(fontSize: 12, color: Colors.blueGrey),
                      ),
                  ],
                ),
              ),
              if (hasBus)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: LIGHT_BLUE,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    'Bus ${student.busNumber}',
                    style: const TextStyle(
                      color: PRIMARY_BLUE,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          const Divider(height: 1),
          const SizedBox(height: 12),
          if (hasBus && hasStop) ...[
            Row(
              children: [
                const Icon(Icons.location_on_outlined, size: 16, color: PRIMARY_BLUE),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    '${languageService.getText('stop')}: ${student.stopName}',
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                  ),
                ),
              ],
            ),
            if (student.stopExpectedTime != null && student.stopExpectedTime!.isNotEmpty) ...[
              const SizedBox(height: 6),
              Row(
                children: [
                  const Icon(Icons.schedule_outlined, size: 16, color: Colors.grey),
                  const SizedBox(width: 6),
                  Text(
                    '${languageService.getText('expected_time')}: ${student.stopExpectedTime}',
                    style: const TextStyle(fontSize: 12, color: Colors.blueGrey),
                  ),
                ],
              ),
            ],
          ] else
            Text(
              languageService.getText('bus_not_assigned'),
              style: TextStyle(
                fontSize: 13,
                color: Colors.amber.shade900,
                fontStyle: FontStyle.italic,
              ),
            ),
        ],
      ),
    );
  }
}
