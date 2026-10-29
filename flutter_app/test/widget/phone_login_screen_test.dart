import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:bustrack/screens/phone_login_screen.dart';
import 'package:bustrack/services/api_client.dart';
import 'package:bustrack/services/session_store.dart';
import '../unit/session_controller_test.dart';

void main() {
  Widget createWidgetUnderTest(SessionController controller) {
    return ChangeNotifierProvider<SessionController>.value(
      value: controller,
      child: const MaterialApp(
        home: PhoneLoginScreen(),
      ),
    );
  }

  testWidgets('Continue button is disabled until exactly 10 digits are typed', (tester) async {
    final controller = SessionController(store: InMemorySessionStore());
    await tester.pumpWidget(createWidgetUnderTest(controller));

    final buttonFinder = find.byKey(const Key('continue_button'));
    expect(buttonFinder, findsOneWidget);

    // Initial state: empty field -> button disabled
    ElevatedButton button = tester.widget(buttonFinder);
    expect(button.onPressed, isNull);

    // Enter 9 digits
    final fieldFinder = find.byType(TextField);
    await tester.enterText(fieldFinder, '987654321');
    await tester.pump();

    button = tester.widget(buttonFinder);
    expect(button.onPressed, isNull);

    // Enter 10th digit
    await tester.enterText(fieldFinder, '9876543210');
    await tester.pump();

    button = tester.widget(buttonFinder);
    expect(button.onPressed, isNotNull);
  });

  testWidgets('Displays 404 not registered error text under the field', (tester) async {
    final mockClient = MockClient((request) async {
      return http.Response(jsonEncode({'detail': 'Not registered'}), 404);
    });
    final client = ApiClient(baseUrl: 'https://example.com', client: mockClient);
    final controller = SessionController(store: InMemorySessionStore(), apiClient: client);

    await tester.pumpWidget(createWidgetUnderTest(controller));

    await tester.enterText(find.byType(TextField), '9876543210');
    await tester.pump();

    await tester.tap(find.byKey(const Key('continue_button')));
    await tester.pump(); // Start request
    await tester.pump(const Duration(milliseconds: 100)); // Complete request

    expect(find.textContaining('This number is not registered with the school'), findsOneWidget);
  });

  testWidgets('Displays 429 too many attempts error text under the field', (tester) async {
    final mockClient = MockClient((request) async {
      return http.Response(jsonEncode({'detail': 'Rate limit'}), 429);
    });
    final client = ApiClient(baseUrl: 'https://example.com', client: mockClient);
    final controller = SessionController(store: InMemorySessionStore(), apiClient: client);

    await tester.pumpWidget(createWidgetUnderTest(controller));

    await tester.enterText(find.byType(TextField), '9876543210');
    await tester.pump();

    await tester.tap(find.byKey(const Key('continue_button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.textContaining('Too many wrong attempts'), findsOneWidget);
  });

  testWidgets('Displays network error text under the field', (tester) async {
    final mockClient = MockClient((request) async {
      throw http.ClientException('Network down');
    });
    final client = ApiClient(baseUrl: 'https://example.com', client: mockClient);
    final controller = SessionController(store: InMemorySessionStore(), apiClient: client);

    await tester.pumpWidget(createWidgetUnderTest(controller));

    await tester.enterText(find.byType(TextField), '9876543210');
    await tester.pump();

    await tester.tap(find.byKey(const Key('continue_button')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.textContaining('No internet connection'), findsOneWidget);
  });
}
