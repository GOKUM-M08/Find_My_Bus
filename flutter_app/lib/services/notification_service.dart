import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

/// Top-level background message handler for FCM.
/// Must be outside any class and annotated with @pragma('vm:entry-point').
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  debugPrint(
      '[FCM Background Message] Title: ${message.notification?.title}, Body: ${message.notification?.body}');
}

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FirebaseMessaging _fcm = FirebaseMessaging.instance;
  bool _initialized = false;

  final StreamController<RemoteMessage> _foregroundMessageController =
      StreamController<RemoteMessage>.broadcast();

  /// Stream of foreground push notifications received while the app is active.
  Stream<RemoteMessage> get onForegroundMessage =>
      _foregroundMessageController.stream;

  /// Initializes FCM permissions, handlers, and prints debug logs.
  Future<void> initialize() async {
    if (_initialized) return;

    try {
      debugPrint('[FCM] Requesting notification permissions...');
      final settings = await _fcm.requestPermission(
        alert: true,
        badge: true,
        sound: true,
        provisional: false,
      );
      debugPrint(
          '[FCM Permission Status] Authorization: ${settings.authorizationStatus}');

      // Register top-level background message handler
      FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

      // Listen to foreground notifications when app is open
      FirebaseMessaging.onMessage.listen((RemoteMessage message) {
        debugPrint(
            '[FCM Foreground Received] Title: ${message.notification?.title}, Body: ${message.notification?.body}');
        _foregroundMessageController.add(message);
      });

      // Listen to notification tap events when app is opened from background
      FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
        debugPrint(
            '[FCM Notification Tapped] Title: ${message.notification?.title}, Data: ${message.data}');
      });

      // Log FCM Device Token for debugging
      final token = await _fcm.getToken();
      debugPrint('[FCM Device Token] $token');

      _initialized = true;
      debugPrint('[FCM Initialization] Completed successfully.');
    } catch (e, stack) {
      debugPrint('[FCM Initialization ERROR] Exception: $e\nStack: $stack');
    }
  }

  /// Subscribes to the FCM topic for a specific bus and stop.
  Future<void> subscribeToStop(String busId, String stopId) async {
    if (!_initialized) {
      await initialize();
    }
    final topic = "bus_${busId}_stop_${stopId}";
    try {
      debugPrint('[FCM Subscribing] Topic: $topic');
      await _fcm.subscribeToTopic(topic);
      debugPrint('[FCM Subscribed SUCCESS] Topic: $topic');
    } catch (e, stack) {
      debugPrint(
          '[FCM Subscription ERROR] Failed to subscribe to topic $topic: $e\nStack: $stack');
    }
  }
}