import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'screens/find_bus_screen.dart';
import 'services/notification_service.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
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

  runApp(const BusTrackApp());
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
      // Check if user is already logged in
            // Parents land here directly — no login required. Drivers
      // reach LoginScreen via the "Driver Login" button on this screen.
      home: const FindBusScreen(),
    );
  }
}