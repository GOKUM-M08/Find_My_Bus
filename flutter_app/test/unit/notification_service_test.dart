import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:bustrack/services/notification_service.dart';
import 'package:bustrack/services/notification_prefs.dart';
import 'package:bustrack/services/session_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late NotificationService notifService;
  late List<String> subscribedTopics;
  late List<String> unsubscribedTopics;

  setUp(() async {
    SharedPreferences.setMockInitialValues({
      'subscribed_topics': ['bus_old_stop_1'],
      'selected_stop_old': '1',
      'notif_enabled': true,
      'notif_lang': 'ta',
    });

    notifService = NotificationService();
    subscribedTopics = [];
    unsubscribedTopics = [];

    notifService.testSubscribeHandler = (topic) async {
      subscribedTopics.add(topic);
    };
    notifService.testUnsubscribeHandler = (topic) async {
      unsubscribedTopics.add(topic);
    };
  });

  test('syncSubscriptions subscribes to multi-language and bus-wide topics (default ta)', () async {
    final students = [
      StudentInfo(
        studentId: 's1',
        studentName: 'Aarav',
        busId: '10',
        stopId: '50',
      ),
      StudentInfo(
        studentId: 's2',
        studentName: 'Diya',
        busId: '20',
        stopId: '60',
      ),
    ];

    final activeTopics = await notifService.syncSubscriptions(students);

    // Old topic 'bus_old_stop_1' should be unsubscribed
    expect(unsubscribedTopics, contains('bus_old_stop_1'));

    // New bilingual stop and all-bus topics should be subscribed in default 'ta'
    expect(subscribedTopics, contains('bus_10_stop_50_ta'));
    expect(subscribedTopics, contains('bus_10_all_ta'));
    expect(subscribedTopics, contains('bus_20_stop_60_ta'));
    expect(subscribedTopics, contains('bus_20_all_ta'));

    // Active topics returned
    expect(activeTopics, contains('bus_10_stop_50_ta'));
    expect(activeTopics, contains('bus_10_all_ta'));
    expect(activeTopics, contains('bus_20_stop_60_ta'));
    expect(activeTopics, contains('bus_20_all_ta'));
    expect(activeTopics.contains('bus_old_stop_1'), isFalse);

    // SharedPreferences should have the new list and cleaned legacy keys
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getStringList('subscribed_topics');
    expect(stored, isNotNull);
    expect(stored!.contains('bus_10_stop_50_ta'), isTrue);
    expect(stored.contains('bus_10_all_ta'), isTrue);
    expect(stored.contains('bus_old_stop_1'), isFalse);

    // Legacy key removed
    expect(prefs.containsKey('selected_stop_old'), isFalse);
  });

  test('syncSubscriptions respects notif_enabled = false by unsubscribing all topics', () async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('notif_enabled', false);
    await prefs.setStringList('subscribed_topics', ['bus_10_stop_50_ta', 'bus_10_all_ta']);

    final students = [
      StudentInfo(
        studentId: 's1',
        studentName: 'Aarav',
        busId: '10',
        stopId: '50',
      ),
    ];

    final activeTopics = await notifService.syncSubscriptions(students);

    // All active topics must be unsubscribed
    expect(unsubscribedTopics, contains('bus_10_stop_50_ta'));
    expect(unsubscribedTopics, contains('bus_10_all_ta'));
    expect(subscribedTopics, isEmpty);
    expect(activeTopics, isEmpty);

    final stored = prefs.getStringList('subscribed_topics');
    expect(stored, isEmpty);
  });

  test('NotificationPrefs triggers resync on setLanguage and setEnabled', () async {
    final students = [
      StudentInfo(
        studentId: 's1',
        studentName: 'Aarav',
        busId: '10',
        stopId: '50',
      ),
    ];

    final notifPrefs = NotificationPrefs();
    await notifPrefs.init();

    // 1. Initial sync in 'ta'
    await notifService.syncSubscriptions(students);
    subscribedTopics.clear();
    unsubscribedTopics.clear();

    // 2. Switch language to 'en'
    await notifPrefs.setLanguage('en', students: students);
    expect(notifPrefs.language, equals('en'));

    // Old 'ta' topics unsubscribed, new 'en' topics subscribed
    expect(unsubscribedTopics, contains('bus_10_stop_50_ta'));
    expect(unsubscribedTopics, contains('bus_10_all_ta'));
    expect(subscribedTopics, contains('bus_10_stop_50_en'));
    expect(subscribedTopics, contains('bus_10_all_en'));

    subscribedTopics.clear();
    unsubscribedTopics.clear();

    // 3. Disable notifications
    await notifPrefs.setEnabled(false, students: students);
    expect(notifPrefs.enabled, isFalse);
    expect(unsubscribedTopics, contains('bus_10_stop_50_en'));
    expect(unsubscribedTopics, contains('bus_10_all_en'));
    expect(subscribedTopics, isEmpty);
  });

  test('syncSubscriptions handles student with no bus or stop gracefully', () async {
    final students = [
      StudentInfo(
        studentId: 's3',
        studentName: 'Rohan',
        busId: null,
        stopId: null,
      ),
      StudentInfo(
        studentId: 's4',
        studentName: 'Priya',
        busId: 'bus_30',
        stopId: '',
      ),
    ];

    final activeTopics = await notifService.syncSubscriptions(students);

    // No valid student topics, so previous 'bus_old_stop_1' should be removed
    expect(unsubscribedTopics, contains('bus_old_stop_1'));
    expect(subscribedTopics, isEmpty);
    expect(activeTopics, isEmpty);

    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getStringList('subscribed_topics');
    expect(stored, isEmpty);
  });
}
