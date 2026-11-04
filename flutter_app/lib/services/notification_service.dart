import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'session_store.dart';

/// Top-level background message handler for FCM.
/// Must be outside any class and annotated with @pragma('vm:entry-point').
///
/// Messages that carry a `notification` block are displayed by Android itself
/// (using the `channel_id` sent by the backend), so nothing else is needed here.
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

  /// Channel IDs MUST match backend/notification_messages.py exactly.
  /// Android fixes a channel's sound when it is first created, so whenever a
  /// sound file changes, bump the version (_v3 -> _v4) here AND in the backend.
  static const List<Map<String, String>> channelDefinitions = [
    {
      'id': 'bus_started_ta_v3',
      'name': 'பேருந்து புறப்பட்டது (Bus Started)',
      'desc': 'பேருந்து முதல் நிறுத்தத்திலிருந்து புறப்படும் போது ஒலிக்கும் அறிவிப்பு',
      'sound': 'bus_started_ta',
    },
    {
      'id': 'bus_near_ta_v3',
      'name': 'பேருந்து அருகில் வருகிறது (Bus Near)',
      'desc': 'பேருந்து 2 நிறுத்தங்களுக்கு முன்பு வரும் போது ஒலிக்கும் அறிவிப்பு',
      'sound': 'bus_near_ta',
    },
    {
      'id': 'bus_arrived_ta_v3',
      'name': 'கல்லூரி அடைந்தது (Bus Reached College)',
      'desc': 'பேருந்து கல்லூரி சென்றடைந்ததும் ஒலிக்கும் அறிவிப்பு',
      'sound': 'bus_arrived_ta',
    },
    {
      'id': 'bus_started_en_v3',
      'name': 'Bus Started',
      'desc': 'Alert when bus departs from the first stop',
      'sound': 'bus_started_en',
    },
    {
      'id': 'bus_near_en_v3',
      'name': 'Bus Near Stop',
      'desc': 'Alert when bus is 2 stops away from your stop',
      'sound': 'bus_near_en',
    },
    {
      'id': 'bus_arrived_en_v3',
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
          debugPrint(
              '[FCM] Created ${channelDefinitions.length} notification channels.');
        }
      } catch (e) {
        debugPrint('[Local Notifications Init Error] $e');
      }

      // Register top-level background message handler
      FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

      // Listen to foreground notifications when app is open
      FirebaseMessaging.onMessage.listen((RemoteMessage message) {
        debugPrint(
            '[FCM Foreground Received] Title: ${message.notification?.title}, Body: ${message.notification?.body}, Data: ${message.data}');
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
          'bus_near_ta_v3';

      final match = channelDefinitions.firstWhere(
        (c) => c['id'] == channelId,
        orElse: () => channelDefinitions[1],
      );
      final soundName = match['sound']!;

      final androidDetails = AndroidNotificationDetails(
        match['id']!,
        match['name']!,
        channelDescription: match['desc'],
        importance: Importance.max,
        priority: Priority.high,
        sound: RawResourceAndroidNotificationSound(soundName),
        playSound: true,
        icon: '@mipmap/ic_launcher',
      );

      final notifDetails = NotificationDetails(android: androidDetails);
      // Millisecond-based id (kept inside the 32-bit range) so two alerts that
      // arrive in the same second do not replace each other.
      final notifId =
          DateTime.now().millisecondsSinceEpoch.remainder(2147483647);
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

  /// Returns true when the subscription succeeded.
  Future<bool> _subscribeTopic(String topic) async {
    if (testSubscribeHandler != null) {
      await testSubscribeHandler!(topic);
      return true;
    }
    try {
      if (!_initialized) {
        await initialize();
      }
      await _fcm.subscribeToTopic(topic);
      return true;
    } catch (e) {
      debugPrint('[FCM Subscribe Topic Error] $topic: $e');
      return false;
    }
  }

  /// Returns true when the unsubscribe succeeded.
  Future<bool> _unsubscribeTopic(String topic) async {
    if (testUnsubscribeHandler != null) {
      await testUnsubscribeHandler!(topic);
      return true;
    }
    try {
      if (!_initialized) {
        await initialize();
      }
      await _fcm.unsubscribeFromTopic(topic);
      return true;
    } catch (e) {
      debugPrint('[FCM Unsubscribe Topic Error] $topic: $e');
      return false;
    }
  }

  /// Automatically synchronizes FCM topic subscriptions for the parent's students.
  /// If [students] is null, falls back to the stored session profile.
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

      // One-time cleanup of the OLD un-suffixed topic (bus_<bus>_stop_<stop>).
      // Messages sent to that topic carry no channel, so Android plays the
      // phone's normal sound. Older installs may still be subscribed to it even
      // though it is not in the saved list, so unsubscribe explicitly.
      // The flag is set only when every unsubscribe succeeded (e.g. online),
      // otherwise this runs again on the next sync.
      if (!(prefs.getBool('legacy_cleanup_done') ?? false) &&
          targetStudents.isNotEmpty) {
        var allOk = true;
        for (final s in targetStudents) {
          final b = s.busId?.toString().trim();
          final st = s.stopId?.toString().trim();
          if (b != null && b.isNotEmpty && st != null && st.isNotEmpty) {
            debugPrint('[FCM Sync] Legacy cleanup: leaving bus_${b}_stop_$st');
            final ok = await _unsubscribeTopic('bus_${b}_stop_$st');
            if (!ok) allOk = false;
          }
        }
        if (allOk) {
          await prefs.setBool('legacy_cleanup_done', true);
          debugPrint('[FCM Sync] Legacy topic cleanup done.');
        }
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

      // 1. Unsubscribe from topics that are no longer wanted (old language,
      //    alerts switched off, different student, legacy topics).
      //    A topic is dropped from the saved list only when the unsubscribe
      //    succeeded, so a failed one is retried on the next sync.
      final toRemove = currentTopics.difference(desiredTopics);
      for (final topic in toRemove) {
        debugPrint('[FCM Sync] Unsubscribing from old topic: $topic');
        final ok = await _unsubscribeTopic(topic);
        if (ok) currentTopics.remove(topic);
      }

      // 2. Subscribe to new topics (added to the saved list only on success).
      final toAdd = desiredTopics.difference(currentTopics);
      for (final topic in toAdd) {
        debugPrint('[FCM Sync] Subscribing to topic: $topic');
        final ok = await _subscribeTopic(topic);
        if (ok) currentTopics.add(topic);
      }

      // 3. Save the active subscribed topics list
      await prefs.setStringList('subscribed_topics', currentTopics.toList());

      // 4. One-time cleanup for old legacy 'selected_stop_*' keys
      try {
        final keys = prefs.getKeys().toList();
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

  // ---------------------------------------------------------------------------
  // Legacy API kept ONLY so older screens still compile.
  // These no longer subscribe to the old un-suffixed topic
  // (bus_<bus>_stop_<stop>); they just re-run syncSubscriptions(), which uses
  // the language-specific topics and the student's real bus and stop.
  // ---------------------------------------------------------------------------

  @Deprecated('Use syncSubscriptions(). Legacy un-suffixed topics are no longer used.')
  Future<void> subscribeToStop(String busId, String stopId) async {
    await syncSubscriptions();
  }

  @Deprecated('Use syncSubscriptions(). Legacy un-suffixed topics are no longer used.')
  Future<void> unsubscribeFromStop(String busId, String stopId) async {
    await syncSubscriptions();
  }

  /// Gets local persisted selected stopId for a bus (legacy fallback).
  Future<String?> getSelectedStopId(String busId) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('selected_stop_$busId');
  }

  @Deprecated('Use syncSubscriptions(). The stop now comes from the student record.')
  Future<void> switchSelectedStop(String busId, String newStopId) async {
    await syncSubscriptions();
  }

  @Deprecated('Use syncSubscriptions(). The stop now comes from the student record.')
  Future<void> clearSelectedStop(String busId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('selected_stop_$busId');
    await syncSubscriptions();
  }
}