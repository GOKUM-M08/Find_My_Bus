import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:bustrack/screens/parent_home_screen.dart';
import 'package:bustrack/services/api_client.dart';
import 'package:bustrack/services/session_store.dart';
import '../unit/session_controller_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Widget createWidgetUnderTest(SessionController controller) {
    return ChangeNotifierProvider<SessionController>.value(
      value: controller,
      child: const MaterialApp(
        home: ParentHomeScreen(),
      ),
    );
  }

  setUp(() {
    SharedPreferences.setMockInitialValues({
      'asked_notification_permission': true,
    });
  });

  testWidgets('Renders single child card with bus badge, stop name and expected time', (tester) async {
    final mockClient = MockClient((request) async {
      if (request.url.path.contains('/live')) {
        return http.Response(
          jsonEncode({
            'latitude': 13.0827,
            'longitude': 80.2707,
            'speed': 25.0,
            'timestamp': DateTime.now().toUtc().toIso8601String(),
          }),
          200,
        );
      }
      return http.Response('{}', 200);
    });

    final apiClient = ApiClient(baseUrl: 'https://example.com', client: mockClient);
    final store = InMemorySessionStore();
    await store.saveSession(
      token: 'valid_jwt',
      profile: ParentProfile(
        phone: '9876543210',
        students: [
          StudentInfo(
            studentId: 's1',
            studentName: 'Aarav Kumar',
            schoolName: 'St. Mary High School',
            busId: 'bus_1',
            busNumber: '42',
            stopId: 'stop_10',
            stopName: 'Anna Nagar Roundtana',
            stopExpectedTime: '08:15 AM',
          ),
        ],
      ),
    );

    final controller = SessionController(store: store, apiClient: apiClient);
    await controller.restore();

    await tester.pumpWidget(createWidgetUnderTest(controller));
    await tester.pumpAndSettle();

    expect(find.text('Aarav Kumar'), findsOneWidget);
    expect(find.text('Bus 42'), findsOneWidget);
    expect(find.text('Anna Nagar Roundtana'), findsOneWidget);
    expect(find.textContaining('08:15 AM'), findsOneWidget);
    expect(find.text('LIVE'), findsOneWidget);
  });

  testWidgets('Renders multiple children cards on different buses', (tester) async {
    final mockClient = MockClient((request) async {
      return http.Response(
        jsonEncode({
          'latitude': 13.0827,
          'longitude': 80.2707,
          'speed': 0.0,
          'timestamp': DateTime.now().toUtc().subtract(const Duration(minutes: 5)).toIso8601String(),
        }),
        200,
      );
    });

    final apiClient = ApiClient(baseUrl: 'https://example.com', client: mockClient);
    final store = InMemorySessionStore();
    await store.saveSession(
      token: 'valid_jwt',
      profile: ParentProfile(
        phone: '9876543210',
        students: [
          StudentInfo(
            studentId: 's1',
            studentName: 'Aarav',
            busId: 'bus_1',
            busNumber: '10',
            stopId: 'stop_1',
            stopName: 'Stop A',
          ),
          StudentInfo(
            studentId: 's2',
            studentName: 'Diya',
            busId: 'bus_2',
            busNumber: '20',
            stopId: 'stop_2',
            stopName: 'Stop B',
          ),
        ],
      ),
    );

    final controller = SessionController(store: store, apiClient: apiClient);
    await controller.restore();

    await tester.pumpWidget(createWidgetUnderTest(controller));
    await tester.pumpAndSettle();

    expect(find.text('Aarav'), findsOneWidget);
    expect(find.text('Bus 10'), findsOneWidget);
    expect(find.text('Diya'), findsOneWidget);
    expect(find.text('Bus 20'), findsOneWidget);
    expect(find.text('Offline'), findsNWidgets(2));
  });

  testWidgets('Renders unassigned bus message for child without bus', (tester) async {
    final mockClient = MockClient((request) async => http.Response('{}', 200));
    final apiClient = ApiClient(baseUrl: 'https://example.com', client: mockClient);
    final store = InMemorySessionStore();
    await store.saveSession(
      token: 'valid_jwt',
      profile: ParentProfile(
        phone: '9876543210',
        students: [
          StudentInfo(
            studentId: 's3',
            studentName: 'Rohan',
            schoolName: 'Govt Model School',
            busId: null,
            stopId: null,
          ),
        ],
      ),
    );

    final controller = SessionController(store: store, apiClient: apiClient);
    await controller.restore();

    await tester.pumpWidget(createWidgetUnderTest(controller));
    await tester.pumpAndSettle();

    expect(find.text('Rohan'), findsOneWidget);
    expect(find.text('Bus not assigned yet. Please contact the school.'), findsOneWidget);
  });
}
