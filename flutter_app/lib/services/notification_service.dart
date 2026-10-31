import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
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

  FlutterLocalNotificationsPlugin? _customLocalNotifications;
  FlutterLocalNotificationsPlugin get localNotifications =>
      _customLocalNotifications ??= FlutterLocalNotificationsPlugin();
  set localNotificationsPlugin(FlutterLocalNotificationsPlugin plugin) =>
      _customLocalNotifications = plugin;

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

  static const List<Map<String, String>> channelDefinitions = [
    {
      'id': 'bus_started_ta_v2',
      'name': 'பேருந்து புறப்பட்டது (Bus Started)',
      'desc': 'பேருந்து முதல் நிறுத்தத்திலிருந்து புறப்படும் போது ஒலிக்கும் அறிவிப்பு',
      'sound': 'bus_started_ta',
    },
    {
      'id': 'bus_near_ta_v2',
      'name': 'பேருந்து அருகில் வருகிறது (Bus Near)',
      'desc': 'பேருந்து 2 நிறுத்தங்களுக்கு முன்பு வரும் போது ஒலிக்கும் அறிவிப்பு',
      'sound': 'bus_near_ta',
    },
    {
      'id': 'bus_arrived_ta_v2',
      'name': 'கல்லூரி அடைந்தது (Bus Reached College)',
      'desc': 'பேருந்து கல்லூரி சென்றடைந்ததும் ஒலிக்கும் அறிவிப்பு',
      'sound': 'bus_arrived_ta',
    },
    {
      'id': 'bus_started_en_v2',
      'name': 'Bus Started',
      'desc': 'Alert when bus departs from the first stop',
      'sound': 'bus_started_en',
    },
    {
      'id': 'bus_near_en_v2',
      'name': 'Bus Near Stop',
      'desc': 'Alert when bus is 2 stops away from your stop',
      'sound': 'bus_near_en',
    },
    {
      'id': 'bus_arrived_en_v2',
      'name': 'Bus Reached College',
      'desc': 'Alert when bus reaches the college campus',
      'sound': 'bus_arrived_en',
    },
  ];

  /// Initializes FCM permissions, native notification channels, and handlers.
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

      // Initialize flutter_local_notifications for channel creation and foreground audio alerts
      try {
        const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
        const initSettings = InitializationSettings(android: androidInit);
        await localNotifications.initialize(settings: initSettings);

        final androidImpl = localNotifications
            .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
        if (androidImpl != null) {
          for (final def in channelDefinitions) {
            final soundName = def['sound']!;
            final channel = AndroidNotificationChannel(
              def['id']!,
              def['name']!,
              description: def['desc'],
              importance: Importance.max,
              sound: RawResourceAndroidNotificationSound(soundName),
              playSound: true,
              enableVibration: true,
            );
            await androidImpl.createNotificationChannel(channel);
          }
        }
      } catch (e) {
        debugPrint('[Local Notifications Init Error] $e');
      }

      // Register top-level background message handler
      FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

      // Listen to foreground notifications when app is open
      FirebaseMessaging.onMessage.listen((RemoteMessage message) {
        debugPrint(
            '[FCM Foreground Received] Title: ${message.notification?.title}, Body: ${message.notification?.body}');
        _foregroundMessageController.add(message);
        _showForegroundNotification(message);
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

  Future<void> _showForegroundNotification(RemoteMessage message) async {
    try {
      final notif = message.notification;
      final title = notif?.title ?? message.data['title'] ?? 'Find My Bus';
      final body = notif?.body ?? message.data['body'] ?? '';

      final channelId = message.data['channel_id']?.toString() ??
          notif?.android?.channelId ??
          'bus_near_ta_v2';

      final match = channelDefinitions.firstWhere(
        (c) => c['id'] == channelId,
        orElse: () => channelDefinitions[1],
      );
      final soundName = match['sound']!;

      final androidDetails = AndroidNotificationDetails(
        channelId,
        match['name']!,
        channelDescription: match['desc'],
        importance: Importance.max,
        priority: Priority.high,
        sound: RawResourceAndroidNotificationSound(soundName),
        playSound: true,
        icon: '@mipmap/ic_launcher',
      );

      final notifDetails = NotificationDetails(android: androidDetails);
      final notifId = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      await localNotifications.show(
        id: notifId,
        title: title,
        body: body,
        notificationDetails: notifDetails,
      );
    } catch (e) {
      debugPrint('[NotificationService foreground show error] $e');
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
  /// If [students] is null, falls back to [SessionStore().parentProfile?.students].
  /// When notif_enabled is false, desiredTopics is empty (all unsubscribed).
  /// When notif_enabled is true, subscribes to:
  /// - `bus_${busId}_stop_${stopId}_${lang}`
  /// - `bus_${busId}_all_${lang}`
  /// Unsubscribes from obsolete/legacy topics and saves active topics in SharedPreferences.
  Future<Set<String>> syncSubscriptions([List<StudentInfo>? students]) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final notifEnabled = prefs.getBool('notif_enabled') ?? true;
      final notifLang = prefs.getString('notif_lang') ?? 'ta';

      List<StudentInfo> targetStudents = students ?? [];
      if (students == null) {
        final profile = await SessionStore.instance.getProfile();
        targetStudents = profile?.students ?? [];
      }
      final desiredTopics = <String>{};

      if (notifEnabled) {
        for (final s in targetStudents) {
          final busId = s.busId?.toString().trim();
          final stopId = s.stopId?.toString().trim();
          if (busId != null && busId.isNotEmpty && stopId != null && stopId.isNotEmpty) {
            desiredTopics.add('bus_${busId}_stop_${stopId}_$notifLang');
            desiredTopics.add('bus_${busId}_all_$notifLang');
          }
        }
      }

      final currentList = prefs.getStringList('subscribed_topics') ?? [];
      final currentTopics = currentList.toSet();

      // 1. Unsubscribe from topics that are no longer associated with active desired topics
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

      // Also clean up any legacy un-suffixed topics for these students
      for (final s in targetStudents) {
        final busId = s.busId?.toString().trim();
        final stopId = s.stopId?.toString().trim();
        if (busId != null && busId.isNotEmpty && stopId != null && stopId.isNotEmpty) {
          final legacyTopic = 'bus_${busId}_stop_$stopId';
          if (currentTopics.contains(legacyTopic)) {
            try {
              debugPrint('[FCM Sync] Unsubscribing from legacy topic: $legacyTopic');
              await _unsubscribeTopic(legacyTopic);
              currentTopics.remove(legacyTopic);
            } catch (e) {
              debugPrint('[FCM Sync Error] Failed to unsubscribe legacy $legacyTopic: $e');
            }
          }
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
      return {};
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
