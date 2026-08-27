import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:firebase_core/firebase_core.dart';
import 'screens/find_bus_screen.dart';
void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Supabase
  await Supabase.initialize(
    url: 'https://mardeektaxigbxlckwzv.supabase.co',
    anonKey: 'sb_publishable_4JqOykRfsu6xjCQ3KegCbw_oVfEj5DK',
  );

  // Firebase disabled for now — set this up in Phase 8 once you've
  // created a Firebase project and added google-services.json.
  // await Firebase.initializeApp();

  runApp(const BusTrackApp());
}

class BusTrackApp extends StatelessWidget {
  const BusTrackApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'BusTrack',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF1E6BFF),
        ),
        useMaterial3: true,
      ),
      // Check if user is already logged in
            // Parents land here directly — no login required. Drivers
      // reach LoginScreen via the "Driver Login" button on this screen.
      home: const FindBusScreen(),
    );
  }
}