import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'admin_dashboard_screen.dart';

// NOTE: This is a demo-only login — the credentials below are
// hardcoded and checked on the phone itself, not verified against a
// real account system. Fine for a pilot/demo, but before handling a
// real school's data this should move to a proper authenticated
// admin account (e.g. a Supabase Auth user with an 'admin' row in
// user_roles, same pattern already used for drivers).
const String _demoAdminSchoolId = 'RMK school';
const String _demoAdminPassword = 'rmkcet@1128';

class AdminLoginScreen extends StatefulWidget {
  const AdminLoginScreen({super.key});

  @override
  State<AdminLoginScreen> createState() => _AdminLoginScreenState();
}

class _AdminLoginScreenState extends State<AdminLoginScreen> {
  final supabase = Supabase.instance.client;
  final _schoolIdController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _loading = false;
  bool _obscurePassword = true;

  Future<void> _login() async {
    final schoolIdInput = _schoolIdController.text.trim();
    final passwordInput = _passwordController.text;

    if (schoolIdInput != _demoAdminSchoolId ||
        passwordInput != _demoAdminPassword) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Invalid School ID or password')),
      );
      return;
    }

   
    setState(() => _loading = true);

    // Fetch all schools and match client-side (trimmed, case-insensitive)
    // instead of relying on an exact database-side match — this is more
    // forgiving of stray whitespace or formatting differences in the
    // stored name that wouldn't be visible just by eyeballing it.
    final allSchools = await supabase.from('schools').select('id, name');

    Map<String, dynamic>? school;
    for (final row in allSchools) {
      final storedName = (row['name'] as String).trim().toLowerCase();
      if (storedName == schoolIdInput.toLowerCase()) {
        school = row;
        break;
      }
    }

    setState(() => _loading = false);

    if (school == null) {
      if (!mounted) return;
      final availableNames =
          allSchools.map((s) => '"${s['name']}"').join(', ');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'No school matched "$schoolIdInput". '
            'Found in database: $availableNames',
          ),
        ),
      );
      return;
    }    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => AdminDashboardScreen(
          schoolId: school!['id'],
          schoolName: school['name'],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF3F5F9),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E6BFF),
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text('Admin Login'),
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.admin_panel_settings,
                  size: 64, color: Color(0xFF1E6BFF)),
              const SizedBox(height: 16),
              const Text(
                'School Admin',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              const Text(
                'Sign in to manage your school\'s buses',
                style: TextStyle(color: Colors.grey),
              ),
              const SizedBox(height: 32),
              TextField(
                controller: _schoolIdController,
                decoration: InputDecoration(
                  labelText: 'School ID',
                  prefixIcon: const Icon(Icons.school_outlined),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _passwordController,
                obscureText: _obscurePassword,
                decoration: InputDecoration(
                  labelText: 'Password',
                  prefixIcon: const Icon(Icons.lock_outline),
                  suffixIcon: IconButton(
                    icon: Icon(_obscurePassword
                        ? Icons.visibility_off
                        : Icons.visibility),
                    onPressed: () => setState(
                        () => _obscurePassword = !_obscurePassword),
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _loading ? null : _login,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1E6BFF),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: _loading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                              color: Colors.white, strokeWidth: 2),
                        )
                      : const Text('Login'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}