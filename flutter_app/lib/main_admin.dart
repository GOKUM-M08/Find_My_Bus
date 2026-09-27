import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'screens/admin_login_screen.dart';

const Color PRIMARY_BLUE = Color(0xFF0052CC);
const Color BACKGROUND_BLUE = Color(0xFFF7F9FC);

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Supabase for Admin Panel Web Entrypoint
  await Supabase.initialize(
    url: 'https://mardeektaxigbxlckwzv.supabase.co',
    anonKey: 'sb_publishable_4JqOykRfsu6xjCQ3KegCbw_oVfEj5DK',
  );

  runApp(const AdminConsoleApp());
}

class AdminConsoleApp extends StatelessWidget {
  const AdminConsoleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Find My Bus Admin Console',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: PRIMARY_BLUE,
        ),
        useMaterial3: true,
        appBarTheme: const AppBarTheme(
          backgroundColor: PRIMARY_BLUE,
          foregroundColor: Colors.white,
          elevation: 2,
        ),
        scaffoldBackgroundColor: BACKGROUND_BLUE,
      ),
      home: const AdminLoginScreen(),
    );
  }
}
