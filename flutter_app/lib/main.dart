import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:provider/provider.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

import 'screens/find_bus_screen.dart';
import 'screens/phone_login_screen.dart';
import 'services/notification_service.dart';
import 'services/session_store.dart';
import 'services/language_service.dart';

// Professional Blue Color Palette
const Color PRIMARY_BLUE = Color(0xFF0052CC);
const Color SECONDARY_BLUE = Color(0xFF1E6BFF);
const Color LIGHT_BLUE = Color(0xFFE8F0FE);
const Color BACKGROUND_BLUE = Color(0xFFF7F9FC);

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Supabase
  await Supabase.initialize(
    url: 'https://mardeektaxigbxlckwzv.supabase.co',
    anonKey: 'sb_publishable_4JqOykRfsu6xjCQ3KegCbw_oVfEj5DK',
  );

  if (!kIsWeb) {
    await Firebase.initializeApp();
    await NotificationService().initialize();
  }

  runApp(
    ChangeNotifierProvider(
      create: (_) => SessionController()..restore(),
      child: const BusTrackApp(),
    ),
  );
}

class BusTrackApp extends StatelessWidget {
  const BusTrackApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Find My Bus',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: PRIMARY_BLUE,
        ),
        useMaterial3: true,
        appBarTheme: const AppBarTheme(
          backgroundColor: PRIMARY_BLUE,
          foregroundColor: Colors.white,
          elevation: 8,
        ),
        scaffoldBackgroundColor: BACKGROUND_BLUE,
      ),
      home: const AppGate(),
    );
  }
}

class AppGate extends StatelessWidget {
  const AppGate({super.key});

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionController>();

    if (session.isLoading) {
      return const SplashScreen();
    } else if (session.isLoggedIn) {
      return const ParentAppHomeWrapper();
    } else {
      return PhoneLoginScreen(
        initialMessage: session.state.logoutReason,
      );
    }
  }
}

class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(22),
              child: Image.asset(
                'assets/icon/icon.png',
                width: 88,
                height: 88,
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => Container(
                  width: 88,
                  height: 88,
                  decoration: BoxDecoration(
                    color: PRIMARY_BLUE.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.directions_bus_rounded,
                    size: 52,
                    color: PRIMARY_BLUE,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'Find My Bus',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Color(0xFF1E293B),
              ),
            ),
            const SizedBox(height: 24),
            const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                color: PRIMARY_BLUE,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class ParentAppHomeWrapper extends StatefulWidget {
  const ParentAppHomeWrapper({super.key});

  @override
  State<ParentAppHomeWrapper> createState() => _ParentAppHomeWrapperState();
}

class _ParentAppHomeWrapperState extends State<ParentAppHomeWrapper> {
  bool _didTriggerRefresh = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_didTriggerRefresh) {
      _didTriggerRefresh = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        context.read<SessionController>().refresh();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionController>();
    final languageService = LanguageService();

    return Column(
      children: [
        if (session.isOffline)
          Material(
            color: Colors.amber.shade800,
            child: SafeArea(
              bottom: false,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.cloud_off, size: 16, color: Colors.white),
                    const SizedBox(width: 8),
                    Text(
                      languageService.getText('offline_banner'),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        const Expanded(child: FindBusScreen()),
      ],
    );
  }
}