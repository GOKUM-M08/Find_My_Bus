import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../services/api_client.dart';
import '../services/language_service.dart';
import '../services/session_store.dart';
import 'login_screen.dart';

const Color kPrimaryBlue = Color(0xFF0052CC);

class PhoneLoginScreen extends StatefulWidget {
  final String? initialMessage;

  const PhoneLoginScreen({super.key, this.initialMessage});

  @override
  State<PhoneLoginScreen> createState() => _PhoneLoginScreenState();
}

class _PhoneLoginScreenState extends State<PhoneLoginScreen> {
  final TextEditingController _phoneController = TextEditingController();
  final FocusNode _phoneFocusNode = FocusNode();
  final LanguageService _languageService = LanguageService();

  bool _isLoading = false;
  bool _showWakeUp = false;
  String? _errorMessage;
  Timer? _wakeUpTimer;

  @override
  void initState() {
    super.initState();
    _languageService.addListener(_onLanguageChanged);
    _phoneController.addListener(_onPhoneChanged);
    if (widget.initialMessage != null) {
      _errorMessage = widget.initialMessage;
    }
  }

  @override
  void dispose() {
    _languageService.removeListener(_onLanguageChanged);
    _phoneController.removeListener(_onPhoneChanged);
    _phoneController.dispose();
    _phoneFocusNode.dispose();
    _wakeUpTimer?.cancel();
    super.dispose();
  }

  void _onLanguageChanged() {
    if (mounted) setState(() {});
  }

  void _onPhoneChanged() {
    if (_errorMessage != null) {
      setState(() => _errorMessage = null);
    } else {
      setState(() {});
    }
  }

  String _cleanDigits(String text) {
    return text.replaceAll(RegExp(r'\D'), '');
  }

  Future<void> _handleLogin() async {
    final digits = _cleanDigits(_phoneController.text);
    if (digits.length != 10) {
      setState(() {
        _errorMessage = _languageService.getText('err_invalid_phone');
      });
      return;
    }

    _phoneFocusNode.unfocus();

    setState(() {
      _isLoading = true;
      _showWakeUp = false;
      _errorMessage = null;
    });

    _wakeUpTimer?.cancel();
    _wakeUpTimer = Timer(const Duration(seconds: 8), () {
      if (mounted && _isLoading) {
        setState(() => _showWakeUp = true);
      }
    });

    try {
      final session = context.read<SessionController>();
      await session.login(digits);
    } on ApiException catch (e) {
      _handleApiException(e);
    } catch (_) {
      if (mounted) {
        setState(() {
          _errorMessage = _languageService.getText('err_server');
        });
      }
    } finally {
      _wakeUpTimer?.cancel();
      if (mounted) {
        setState(() {
          _isLoading = false;
          _showWakeUp = false;
        });
      }
    }
  }

  void _handleApiException(ApiException e) {
    if (!mounted) return;
    String mapped;
    switch (e.kind) {
      case ApiExceptionKind.notFound:
        mapped = _languageService.getText('err_not_registered');
        break;
      case ApiExceptionKind.tooManyAttempts:
        mapped = _languageService.getText('err_too_many_attempts');
        break;
      case ApiExceptionKind.network:
        mapped = _languageService.getText('err_network');
        break;
      case ApiExceptionKind.timeout:
        mapped = _languageService.getText('err_timeout');
        break;
      case ApiExceptionKind.server:
        if (e.statusCode == 400) {
          mapped = _languageService.getText('err_invalid_phone');
        } else {
          mapped = _languageService.getText('err_server');
        }
        break;
      case ApiExceptionKind.unauthorized:
        mapped = _languageService.getText('please_login_again');
        break;
      case ApiExceptionKind.forbidden:
        mapped = e.message;
        break;
    }
    setState(() => _errorMessage = mapped);
  }

  @override
  Widget build(BuildContext context) {
    final cleanDigits = _cleanDigits(_phoneController.text);
    final isButtonEnabled = cleanDigits.length == 10 && !_isLoading;

    return PopScope(
      canPop: true,
      child: Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          systemOverlayStyle: SystemUiOverlayStyle.dark,
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 8.0),
              child: TextButton.icon(
                style: TextButton.styleFrom(
                  minimumSize: const Size(48, 48),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                ),
                icon: const Icon(Icons.language, color: kPrimaryBlue),
                label: Text(
                  _languageService.isTamil ? 'English' : 'தமிழ்',
                  style: const TextStyle(
                    color: kPrimaryBlue,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
                onPressed: () => _languageService.toggleLanguage(),
              ),
            ),
          ],
        ),
        body: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              return SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 8.0),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    minHeight: constraints.maxHeight - 16,
                  ),
                  child: IntrinsicHeight(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const SizedBox(height: 16),
                        // Bus Icon in rounded blue circle
                        Center(
                          child: Container(
                            width: 80,
                            height: 80,
                            decoration: BoxDecoration(
                              color: kPrimaryBlue.withValues(alpha: 0.1),
                              shape: BoxShape.circle,
                            ),
                            child: const Center(
                              child: Icon(
                                Icons.directions_bus_rounded,
                                size: 44,
                                color: kPrimaryBlue,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 20),
                        // App Title
                        Text(
                          _languageService.getText('login_title'),
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 26,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF1E293B),
                          ),
                        ),
                        const SizedBox(height: 8),
                        // Subtitle
                        Text(
                          _languageService.getText('login_subtitle'),
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 15,
                            color: Colors.grey.shade600,
                            height: 1.3,
                          ),
                        ),
                        const SizedBox(height: 36),

                        // Phone Number Input
                        Container(
                          decoration: BoxDecoration(
                            color: const Color(0xFFF8FAFC),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: _errorMessage != null
                                  ? Colors.red.shade400
                                  : (_phoneFocusNode.hasFocus ? kPrimaryBlue : Colors.grey.shade300),
                              width: _phoneFocusNode.hasFocus ? 1.8 : 1.0,
                            ),
                          ),
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                          child: Row(
                            children: [
                              // Fixed +91 prefix
                              const Text(
                                '+91',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFF1E293B),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                width: 1,
                                height: 26,
                                color: Colors.grey.shade300,
                              ),
                              const SizedBox(width: 12),
                              // Input Field
                              Expanded(
                                child: TextField(
                                  controller: _phoneController,
                                  focusNode: _phoneFocusNode,
                                  enabled: !_isLoading,
                                  keyboardType: TextInputType.phone,
                                  inputFormatters: [
                                    FilteringTextInputFormatter.digitsOnly,
                                    LengthLimitingTextInputFormatter(10),
                                  ],
                                  autofillHints: const [AutofillHints.telephoneNumberNational],
                                  style: const TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w600,
                                    letterSpacing: 1.2,
                                    color: Color(0xFF0F172A),
                                  ),
                                  decoration: InputDecoration(
                                    hintText: _languageService.getText('phone_hint'),
                                    hintStyle: TextStyle(
                                      color: Colors.grey.shade400,
                                      fontSize: 16,
                                      letterSpacing: 0,
                                      fontWeight: FontWeight.normal,
                                    ),
                                    border: InputBorder.none,
                                    contentPadding: const EdgeInsets.symmetric(vertical: 14),
                                  ),
                                ),
                              ),
                              // Visible clear button
                              if (_phoneController.text.isNotEmpty && !_isLoading)
                                IconButton(
                                  icon: const Icon(Icons.clear, size: 20, color: Colors.grey),
                                  tooltip: 'Clear',
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                                  onPressed: () => _phoneController.clear(),
                                ),
                            ],
                          ),
                        ),

                        // Error text in red under the field
                        if (_errorMessage != null) ...[
                          const SizedBox(height: 8),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Icon(Icons.error_outline, size: 16, color: Colors.red),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  _errorMessage!,
                                  style: const TextStyle(
                                    color: Colors.red,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],

                        const SizedBox(height: 24),

                        // Continue Button
                        SizedBox(
                          height: 52,
                          child: ElevatedButton(
                            key: const Key('continue_button'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: kPrimaryBlue,
                              foregroundColor: Colors.white,
                              disabledBackgroundColor: Colors.grey.shade300,
                              disabledForegroundColor: Colors.grey.shade500,
                              elevation: isButtonEnabled ? 2 : 0,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            onPressed: isButtonEnabled ? _handleLogin : null,
                            child: _isLoading
                                ? const SizedBox(
                                    width: 24,
                                    height: 24,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2.5,
                                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                    ),
                                  )
                                : Text(
                                    _languageService.getText('continue_btn'),
                                    style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                      letterSpacing: 0.5,
                                    ),
                                  ),
                          ),
                        ),

                        // 8-second wake up message
                        if (_showWakeUp) ...[
                          const SizedBox(height: 12),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(strokeWidth: 2, color: kPrimaryBlue),
                              ),
                              const SizedBox(width: 8),
                              Flexible(
                                child: Text(
                                  _languageService.getText('server_waking_up'),
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey.shade700,
                                    fontStyle: FontStyle.italic,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],

                        const SizedBox(height: 12),
                        // Helper text under the button
                        Text(
                          _languageService.getText('login_helper'),
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.grey.shade600,
                          ),
                        ),

                        const Spacer(),

                        // Driver Login link kept working
                        Padding(
                          padding: const EdgeInsets.only(top: 16, bottom: 8),
                          child: Center(
                            child: TextButton.icon(
                              style: TextButton.styleFrom(
                                minimumSize: const Size(48, 48),
                                foregroundColor: Colors.grey.shade700,
                              ),
                              icon: const Icon(Icons.drive_eta_outlined, size: 20),
                              label: Text(_languageService.getText('driver_login')),
                              onPressed: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(builder: (_) => const LoginScreen()),
                                );
                              },
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
