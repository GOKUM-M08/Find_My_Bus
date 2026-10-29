import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:bustrack/screens/profile_screen.dart';
import 'package:bustrack/services/session_store.dart';
import '../unit/session_controller_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Widget createWidgetUnderTest(SessionController controller) {
    return ChangeNotifierProvider<SessionController>.value(
      value: controller,
      child: const MaterialApp(
        home: ProfileScreen(),
      ),
    );
  }

  testWidgets('Renders real parent profile and students, with no placeholder strings', (tester) async {
    final store = InMemorySessionStore();
    await store.saveSession(
      token: 'jwt_test',
      profile: ParentProfile(
        phone: '9876543210',
        students: [
          StudentInfo(
            studentId: 's1',
            studentName: 'Kavya Raman',
            parentName: 'Ramanathan S',
            schoolName: 'Chennai Public School',
            schoolPhone: '9444123456',
            busId: 'b_7',
            busNumber: '07',
            stopId: 'st_12',
            stopName: 'T. Nagar Bus Terminus',
            stopExpectedTime: '07:45 AM',
          ),
        ],
      ),
    );

    final controller = SessionController(store: store);
    await controller.restore();

    await tester.pumpWidget(createWidgetUnderTest(controller));
    await tester.pumpAndSettle();

    // Verify real parent details
    expect(find.text('Ramanathan S'), findsOneWidget);
    expect(find.text('+91 98765 43210'), findsOneWidget);

    // Verify real student details
    expect(find.text('Kavya Raman'), findsOneWidget);
    expect(find.text('Chennai Public School'), findsNWidgets(2)); // in student card and helpdesk
    expect(find.text('Bus 07'), findsOneWidget);
    expect(find.textContaining('T. Nagar Bus Terminus'), findsOneWidget);
    expect(find.textContaining('07:45 AM'), findsOneWidget);

    // Verify real school helpdesk
    expect(find.text('+91 94441 23456'), findsOneWidget);
    expect(find.text('Call School'), findsOneWidget);

    // Verify placeholder strings are completely absent
    expect(find.text('Parent / Student Guest'), findsNothing);
    expect(find.text('Bus #101 — St. John School'), findsNothing);
    expect(find.text('Bus #204 — Green Alley Route'), findsNothing);
    expect(find.text('Find My Bus Mobile v1.2'), findsNothing);
  });
}
