import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'session_store.dart';

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

  FirebaseMessaging? _customFcm;
  FirebaseMessaging get _fcm => _customFcm ??= FirebaseMessaging.instance;
  set fcmInstance(FirebaseMessaging messaging) => _customFcm = messaging;
  bool _initialized = false;

  /// Test hooks for unit testing without Firebase native channel.
  @visibleForTesting
  Future<void> Function(String topic)? testSubscribeHandler;
  @visibleForTesting
  Future<void> Function(String topic)? testUnsubscribeHandler;

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

  Future<void> _subscribeTopic(String topic) async {
    if (testSubscribeHandler != null) {
      await testSubscribeHandler!(topic);
      return;
    }
    try {
      if (!_initialized) {
        await initialize();
      }
      await _fcm.subscribeToTopic(topic);
    } catch (e) {
      debugPrint('[FCM Subscribe Topic Error] $e');
    }
  }

  Future<void> _unsubscribeTopic(String topic) async {
    if (testUnsubscribeHandler != null) {
      await testUnsubscribeHandler!(topic);
      return;
    }
    try {
      if (!_initialized) {
        await initialize();
      }
      await _fcm.unsubscribeFromTopic(topic);
    } catch (e) {
      debugPrint('[FCM Unsubscribe Topic Error] $e');
    }
  }

  /// Automatically synchronizes FCM topic subscriptions for the parent's students.
  /// Desired topics: `bus_${student.busId}_stop_${student.stopId}`.
  /// Unsubscribes from old topics, subscribes to new topics, and updates SharedPreferences ('subscribed_topics').
  Future<Set<String>> syncSubscriptions(List<StudentInfo> students) async {
    final desiredTopics = <String>{};
    for (final s in students) {
      final busId = s.busId?.toString().trim();
      final stopId = s.stopId?.toString().trim();
      if (busId != null && busId.isNotEmpty && stopId != null && stopId.isNotEmpty) {
        desiredTopics.add('bus_${busId}_stop_${stopId}');
      }
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      final currentList = prefs.getStringList('subscribed_topics') ?? [];
      final currentTopics = currentList.toSet();

      // 1. Unsubscribe from topics that are no longer associated with any student
      final toRemove = currentTopics.difference(desiredTopics);
      for (final topic in toRemove) {
        try {
          debugPrint('[FCM Sync] Unsubscribing from old topic: $topic');
          await _unsubscribeTopic(topic);
          currentTopics.remove(topic);
        } catch (e) {
          debugPrint('[FCM Sync Error] Failed to unsubscribe from $topic: $e');
        }
      }

      // 2. Subscribe to new topics
      final toAdd = desiredTopics.difference(currentTopics);
      for (final topic in toAdd) {
        try {
          debugPrint('[FCM Sync] Subscribing to topic: $topic');
          await _subscribeTopic(topic);
          currentTopics.add(topic);
        } catch (e) {
          debugPrint('[FCM Sync Error] Failed to subscribe to $topic: $e');
        }
      }

      // 3. Save the active subscribed topics list
      await prefs.setStringList('subscribed_topics', currentTopics.toList());

      // 4. One-time cleanup for old legacy 'selected_stop_*' keys
      try {
        final keys = prefs.getKeys();
        for (final key in keys) {
          if (key.startsWith('selected_stop_')) {
            await prefs.remove(key);
          }
        }
      } catch (_) {}

      return currentTopics;
    } catch (e) {
      debugPrint('[NotificationService syncSubscriptions error] $e');
      return desiredTopics;
    }
  }

  /// Subscribes to the FCM topic for a specific bus and stop.
  Future<void> subscribeToStop(String busId, String stopId) async {
    final topic = "bus_${busId}_stop_${stopId}";
    await _subscribeTopic(topic);
  }

  /// Unsubscribes from the FCM topic for a specific bus and stop.
  Future<void> unsubscribeFromStop(String busId, String stopId) async {
    final topic = "bus_${busId}_stop_${stopId}";
    await _unsubscribeTopic(topic);
  }

  /// Gets local persisted selected stopId for a bus (legacy fallback).
  Future<String?> getSelectedStopId(String busId) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('selected_stop_$busId');
  }

  /// Sets local persisted selected stopId for a bus (legacy fallback).
  Future<void> switchSelectedStop(String busId, String newStopId) async {
    final oldStopId = await getSelectedStopId(busId);
    if (oldStopId != null && oldStopId != newStopId) {
      await unsubscribeFromStop(busId, oldStopId);
    }
    await subscribeToStop(busId, newStopId);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('selected_stop_$busId', newStopId);
  }

  /// Clears selected notification stop for a bus (legacy fallback).
  Future<void> clearSelectedStop(String busId) async {
    final oldStopId = await getSelectedStopId(busId);
    if (oldStopId != null) {
      await unsubscribeFromStop(busId, oldStopId);
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('selected_stop_$busId');
  }
}