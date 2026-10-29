import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:bustrack/services/api_client.dart';
import 'package:bustrack/services/session_store.dart';

class InMemorySessionStore extends SessionStore {
  final Map<String, String> _storage = {};

  @override
  Future<void> saveSession({required String token, required ParentProfile profile}) async {
    _storage['token'] = token;
    _storage['profile'] = jsonEncode(profile.toJson());
  }

  @override
  Future<void> saveProfile(ParentProfile profile) async {
    _storage['profile'] = jsonEncode(profile.toJson());
  }

  @override
  Future<String?> getToken() async => _storage['token'];

  @override
  Future<ParentProfile?> getProfile() async {
    final raw = _storage['profile'];
    if (raw == null) return null;
    return ParentProfile.fromJson(jsonDecode(raw));
  }

  @override
  Future<void> clear() async {
    _storage.clear();
  }
}

void main() {
  group('SessionController Logic', () {
    test('restore with empty store results in loggedOut state', () async {
      final store = InMemorySessionStore();
      final controller = SessionController(store: store);

      await controller.restore();
      expect(controller.isLoggedIn, isFalse);
      expect(controller.state.status, SessionStatus.loggedOut);
    });

    test('restore with saved token and profile restores loggedIn state', () async {
      final store = InMemorySessionStore();
      final profile = ParentProfile(
        phone: '9876543210',
        students: [
          StudentInfo(studentId: 'st-1', studentName: 'Ramu', busId: 'bus-1', stopId: 'stop-1'),
        ],
      );
      await store.saveSession(token: 'existing-jwt', profile: profile);

      final controller = SessionController(store: store);
      await controller.restore();

      expect(controller.isLoggedIn, isTrue);
      expect(controller.token, 'existing-jwt');
      expect(controller.profile?.phone, '9876543210');
      expect(controller.profile?.students.first.studentName, 'Ramu');
    });

    test('login successfully saves session and sets state to loggedIn', () async {
      final store = InMemorySessionStore();
      final mockClient = MockClient((request) async {
        return http.Response(
          jsonEncode({
            'token': 'new-parent-token',
            'phone': '9876543210',
            'students': [
              {'student_id': 'st-1', 'student_name': 'Ramu'},
            ],
          }),
          200,
        );
      });
      final apiClient = ApiClient(baseUrl: 'https://example.com', client: mockClient);
      final controller = SessionController(store: store, apiClient: apiClient);

      final profile = await controller.login('9876543210');
      expect(controller.isLoggedIn, isTrue);
      expect(controller.token, 'new-parent-token');
      expect(profile.phone, '9876543210');

      // Verify persistent in store
      expect(await store.getToken(), 'new-parent-token');
    });

    test('401 during refresh clears session and transitions to loggedOut with reason', () async {
      final store = InMemorySessionStore();
      await store.saveSession(
        token: 'invalid-token',
        profile: ParentProfile(phone: '9876543210', students: []),
      );

      final mockClient = MockClient((request) async {
        return http.Response(jsonEncode({'detail': 'This number is no longer registered'}), 401);
      });
      final apiClient = ApiClient(baseUrl: 'https://example.com', client: mockClient);
      final controller = SessionController(store: store, apiClient: apiClient);

      await controller.restore();
      expect(controller.isLoggedIn, isTrue);

      await controller.refresh();
      expect(controller.isLoggedIn, isFalse);
      expect(controller.state.status, SessionStatus.loggedOut);
      expect(controller.state.logoutReason, 'Please log in again');
      expect(await store.getToken(), isNull);
    });

    test('offline network error during refresh keeps saved profile and sets isOffline true', () async {
      final store = InMemorySessionStore();
      await store.saveSession(
        token: 'valid-token',
        profile: ParentProfile(
          phone: '9876543210',
          students: [StudentInfo(studentId: 'st-1', studentName: 'Ramu')],
        ),
      );

      final mockClient = MockClient((request) async {
        throw http.ClientException('No internet');
      });
      final apiClient = ApiClient(baseUrl: 'https://example.com', client: mockClient);
      final controller = SessionController(store: store, apiClient: apiClient);

      await controller.restore();
      expect(controller.isLoggedIn, isTrue);
      expect(controller.isOffline, isFalse);

      await controller.refresh();
      // Must NOT log out
      expect(controller.isLoggedIn, isTrue);
      expect(controller.isOffline, isTrue);
      expect(controller.profile?.students.first.studentName, 'Ramu');
      expect(await store.getToken(), 'valid-token');
    });
  });
}
