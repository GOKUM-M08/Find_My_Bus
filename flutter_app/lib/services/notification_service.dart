// lib/services/notification_service.dart
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class NotificationService {
  final _messaging = FirebaseMessaging.instance;
  final _supabase = Supabase.instance.client;

  Future<void> init(String studentId) async {
    // Request permission
    await _messaging.requestPermission();

    // Get FCM token and save to database
    final token = await _messaging.getToken();
    if (token != null) {
      await _supabase
          .from('students')
          .update({'fcm_token': token})
          .eq('id', studentId);
    }

    // Handle foreground messages
    FirebaseMessaging.onMessage.listen((message) {
      print('Notification: ${message.notification?.title}');
      // Show in-app notification here
    });
  }
}