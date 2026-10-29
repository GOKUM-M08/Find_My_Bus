import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:bustrack/main.dart';
import 'package:bustrack/services/session_store.dart';
import 'unit/session_controller_test.dart';

void main() {
  testWidgets('App shows splash then phone login when not logged in', (tester) async {
    final store = InMemorySessionStore();
    final controller = SessionController(store: store);

    await tester.pumpWidget(
      ChangeNotifierProvider<SessionController>.value(
        value: controller,
        child: const BusTrackApp(),
      ),
    );

    // Initial state is loading -> shows SplashScreen
    expect(find.byType(SplashScreen), findsOneWidget);

    // Call restore -> transitions to loggedOut
    await controller.restore();
    await tester.pumpAndSettle();

    // Now shows login screen
    expect(find.text('Find My Bus'), findsWidgets);
    expect(find.text('Enter the mobile number you gave your school'), findsOneWidget);
  });
}
