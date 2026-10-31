import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:bustrack/screens/notification_settings_screen.dart';
import 'package:bustrack/services/notification_prefs.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({
      'notif_enabled': true,
      'notif_lang': 'ta',
      'subscribed_topics': <String>[],
    });
    final prefs = NotificationPrefs();
    await prefs.setEnabled(true);
    await prefs.setLanguage('ta');
  });

  testWidgets('NotificationSettingsScreen renders title, toggle, language, and permission cards',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: NotificationSettingsScreen(),
      ),
    );
    await tester.pumpAndSettle();

    // Verify header / title in AppBar
    expect(find.widgetWithText(AppBar, 'Notification Settings'), findsOneWidget);

    // Verify master toggle
    expect(find.byType(SwitchListTile), findsOneWidget);
    expect(find.text('Bus alerts'), findsOneWidget);

    // Verify language options
    expect(find.text('தமிழ் (Tamil)'), findsOneWidget);
    expect(find.text('English'), findsOneWidget);

    // Verify battery optimization card by scrolling down
    final tipFinder = find.textContaining('Lock Screen Reliability Tip');
    await tester.scrollUntilVisible(tipFinder, 100);
    expect(tipFinder, findsOneWidget);
  });

  testWidgets('Toggling Bus alerts updates NotificationPrefs',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: NotificationSettingsScreen(),
      ),
    );
    await tester.pumpAndSettle();

    final switchFinder = find.byType(Switch);
    expect(switchFinder, findsOneWidget);

    // Switch should currently be true
    expect(NotificationPrefs().enabled, isTrue);

    // Tap switch to turn off
    await tester.tap(switchFinder);
    await tester.pumpAndSettle();

    expect(NotificationPrefs().enabled, isFalse);
  });

  testWidgets('Selecting language updates NotificationPrefs',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: NotificationSettingsScreen(),
      ),
    );
    await tester.pumpAndSettle();

    // Tap English radio option
    final englishFinder = find.text('English');
    expect(englishFinder, findsOneWidget);

    await tester.tap(englishFinder);
    await tester.pumpAndSettle();

    expect(NotificationPrefs().language, equals('en'));
  });
}
