import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'home_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _phoneController = TextEditingController();
  final _otpController = TextEditingController();
  bool _otpSent = false;
  bool _loading = false;

  final supabase = Supabase.instance.client;

  Future<void> _sendOTP() async {
    setState(() => _loading = true);
    try {
      await supabase.auth.signInWithOtp(
        phone: '+91${_phoneController.text.trim()}',
      );
      setState(() => _otpSent = true);
    } catch (e) {
      _showError('Failed to send OTP: $e');
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _verifyOTP() async {
    setState(() => _loading = true);
    try {
      final response = await supabase.auth.verifyOTP(
        type: OtpType.sms,
        phone: '+91${_phoneController.text.trim()}',
        token: _otpController.text.trim(),
      );
      if (response.user != null && mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const HomeScreen()),
        );
      }
    } catch (e) {
      _showError('Invalid OTP. Try again.');
    } finally {
      setState(() => _loading = false);
    }
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.directions_bus,
                  size: 64, color: Color(0xFF1E6BFF)),
              const SizedBox(height: 24),
              const Text('BusTrack',
                  style: TextStyle(
                      fontSize: 32, fontWeight: FontWeight.bold)),
              const Text('Know where your child\'s bus is, always.',
                  style: TextStyle(color: Colors.grey)),
              const SizedBox(height: 48),
              
              // Phone number field
              TextField(
                controller: _phoneController,
                keyboardType: TextInputType.phone,
                maxLength: 10,
                decoration: const InputDecoration(
                  prefixText: '+91 ',
                  labelText: 'Mobile Number',
                  border: OutlineInputBorder(),
                ),
              ),

              if (_otpSent) ...[
                const SizedBox(height: 16),
                TextField(
                  controller: _otpController,
                  keyboardType: TextInputType.number,
                  maxLength: 6,
                  decoration: const InputDecoration(
                    labelText: 'Enter OTP',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],

              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1E6BFF),
                    foregroundColor: Colors.white,
                  ),
                  onPressed: _loading
                      ? null
                      : _otpSent ? _verifyOTP : _sendOTP,
                  child: _loading
                      ? const CircularProgressIndicator(color: Colors.white)
                      : Text(_otpSent ? 'Verify OTP' : 'Send OTP',
                          style: const TextStyle(fontSize: 16)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}