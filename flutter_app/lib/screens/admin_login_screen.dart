import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'admin_dashboard_screen.dart';

const Color kPrimaryBlue = Color(0xFF0052CC);
const Color kBackgroundSlate = Color(0xFFF7F9FC);
const Color kTextPrimary = Color(0xFF0F172A);
const Color kTextSecondary = Color(0xFF64748B);
const Color kDangerRed = Color(0xFFEF4444);

class AdminLoginScreen extends StatefulWidget {
  const AdminLoginScreen({super.key});

  @override
  State<AdminLoginScreen> createState() => _AdminLoginScreenState();
}

class _AdminLoginScreenState extends State<AdminLoginScreen> {
  final supabase = Supabase.instance.client;
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _loading = false;
  bool _obscurePassword = true;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    final emailInput = _emailController.text.trim();
    final passwordInput = _passwordController.text;

    if (emailInput.isEmpty || passwordInput.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter both Admin Email and Password.'),
          backgroundColor: kDangerRed,
        ),
      );
      return;
    }

    setState(() => _loading = true);

    try {
      // 1. Authenticate against Supabase Auth
      final authResponse = await supabase.auth.signInWithPassword(
        email: emailInput,
        password: passwordInput,
      );

      final user = authResponse.user;
      if (user == null) {
        throw const AuthException('Authentication failed: No user context returned.');
      }

      // 2. Query user_roles table for user_id = user.id
      final roleRow = await supabase
          .from('user_roles')
          .select('role, school_id')
          .eq('user_id', user.id)
          .maybeSingle();

      if (roleRow == null || roleRow['role'] != 'admin') {
        // Revoke active session if role is not admin
        await supabase.auth.signOut();
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Access denied: User account is not an authorized School Admin.'),
            backgroundColor: kDangerRed,
          ),
        );
        return;
      }

      final schoolId = roleRow['school_id'] as String?;
      if (schoolId == null || schoolId.isEmpty) {
        await supabase.auth.signOut();
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Access denied: No school ID assigned to this admin account.'),
            backgroundColor: kDangerRed,
          ),
        );
        return;
      }

      // 3. Fetch school metadata from schools table
      final schoolRow = await supabase
          .from('schools')
          .select('name')
          .eq('id', schoolId)
          .maybeSingle();

      final schoolName = (schoolRow != null && schoolRow['name'] != null)
          ? (schoolRow['name'] as String).trim()
          : 'School Admin Console';

      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => AdminDashboardScreen(
            schoolId: schoolId,
            schoolName: schoolName,
          ),
        ),
      );
    } on AuthException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Authentication failed: ${error.message}'),
          backgroundColor: kDangerRed,
        ),
      );
    } on PostgrestException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Database verification error: ${error.message}'),
          backgroundColor: kDangerRed,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Sign in error: $e'),
          backgroundColor: kDangerRed,
        ),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBackgroundSlate,
      appBar: AppBar(
        backgroundColor: kPrimaryBlue,
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text('Admin Security Portal'),
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.admin_panel_settings_rounded,
                size: 64,
                color: kPrimaryBlue,
              ),
              const SizedBox(height: 16),
              const Text(
                'School Admin Authentication',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: kTextPrimary,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'Sign in with your registered admin credentials',
                style: TextStyle(color: kTextSecondary, fontSize: 13),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 28),
              TextField(
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                decoration: InputDecoration(
                  labelText: 'Admin Email',
                  prefixIcon: const Icon(Icons.email_outlined),
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
                    onPressed: () =>
                        setState(() => _obscurePassword = !_obscurePassword),
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
                    backgroundColor: kPrimaryBlue,
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
                      : const Text(
                          'Authenticate & Sign In',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
