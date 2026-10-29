import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:bustrack/services/notification_service.dart';
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

  test('syncSubscriptions unsubscribes from obsolete topics and subscribes to active student stops', () async {
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

    // New topics should be subscribed
    expect(subscribedTopics, contains('bus_10_stop_50'));
    expect(subscribedTopics, contains('bus_20_stop_60'));

    // Active topics returned
    expect(activeTopics, contains('bus_10_stop_50'));
    expect(activeTopics, contains('bus_20_stop_60'));
    expect(activeTopics.contains('bus_old_stop_1'), isFalse);

    // SharedPreferences should have the new list and cleaned legacy keys
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getStringList('subscribed_topics');
    expect(stored, isNotNull);
    expect(stored!.contains('bus_10_stop_50'), isTrue);
    expect(stored.contains('bus_20_stop_60'), isTrue);
    expect(stored.contains('bus_old_stop_1'), isFalse);

    // Legacy key removed
    expect(prefs.containsKey('selected_stop_old'), isFalse);
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
