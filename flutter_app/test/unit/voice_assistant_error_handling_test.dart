import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:bustrack/services/session_store.dart';
import 'package:bustrack/services/voice_assistant_service.dart';

class MockSessionStore extends SessionStore {
  String? token;
  MockSessionStore([this.token = 'test_token']);

  @override
  Future<String?> getToken() async => token;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SessionStore originalSessionStore;
  late MockSessionStore mockStore;

  setUp(() {
    originalSessionStore = SessionStore.instance;
    mockStore = MockSessionStore('valid_jwt_token');
    SessionStore.instance = mockStore;
  });

  tearDown(() {
    SessionStore.instance = originalSessionStore;
  });

  group('VoiceAssistantService Error Handling - 5 Specific Error Conditions', () {
    // -------------------------------------------------------------
    // 1. NO INTERNET
    // -------------------------------------------------------------
    test('Condition 1: No internet (SocketException / ClientException / Timeout) returns specific network error', () async {
      final client = MockClient((request) async {
        throw http.ClientException('Failed host lookup: find-my-bus-teu4.onrender.com');
      });

      final service = VoiceAssistantService(httpClient: client);

      // English query
      final enResponse = await service.handleQuery(
        recognizedText: 'where is the bus',
        busId: 'bus_10',
      );
      expect(enResponse, 'No internet connection. Please check your network and try again.');

      // Tamil query
      final taResponse = await service.handleQuery(
        recognizedText: 'பேருந்து எங்கே இருக்கு',
        busId: 'bus_10',
      );
      expect(taResponse, 'இணைய இணைப்பு இல்லை. உங்கள் நெட்வொர்க்கைச் சரிபார்த்து மீண்டும் முயற்சிக்கவும்.');
    });

    test('Condition 1b: Request timeout returns specific network error', () async {
      final client = MockClient((request) async {
        throw TimeoutException('Request timed out after 8s');
      });

      final service = VoiceAssistantService(httpClient: client);

      final enResponse = await service.handleQuery(
        recognizedText: 'when will the bus arrive',
        busId: 'bus_10',
      );
      expect(enResponse, 'No internet connection. Please check your network and try again.');
    });

    // -------------------------------------------------------------
    // 2. NOT LOGGED IN (401)
    // -------------------------------------------------------------
    test('Condition 2a: Missing/empty token returns specific unauthorized error', () async {
      mockStore.token = null; // No token saved
      final client = MockClient((request) async => http.Response('{}', 200));

      final service = VoiceAssistantService(httpClient: client);

      // English
      final enResponse = await service.handleQuery(
        recognizedText: 'where is the bus',
        busId: 'bus_10',
      );
      expect(enResponse, 'You are not logged in. Please log in again to track this bus.');

      // Tamil
      final taResponse = await service.handleQuery(
        recognizedText: 'பேருந்து எங்கே',
        busId: 'bus_10',
      );
      expect(taResponse, 'நீங்கள் உள்நுழையவில்லை. இந்த பேருந்தைக் கண்காணிக்க மீண்டும் உள்நுழையவும்.');
    });

    test('Condition 2b: Backend returns 401 Unauthorized returns specific unauthorized error', () async {
      final client = MockClient((request) async {
        return http.Response(
          jsonEncode({'detail': 'Please log in again.'}),
          401,
          headers: {'content-type': 'application/json'},
        );
      });

      final service = VoiceAssistantService(httpClient: client);

      // English
      final enResponse = await service.handleQuery(
        recognizedText: 'where is the bus',
        busId: 'bus_10',
      );
      expect(enResponse, 'You are not logged in. Please log in again to track this bus.');

      // Tamil
      final taResponse = await service.handleQuery(
        recognizedText: 'பேருந்து எங்கே இருக்கு',
        busId: 'bus_10',
      );
      expect(taResponse, 'நீங்கள் உள்நுழையவில்லை. இந்த பேருந்தைக் கண்காணிக்க மீண்டும் உள்நுழையவும்.');
    });

    // -------------------------------------------------------------
    // 3. BUS NOT LINKED (403)
    // -------------------------------------------------------------
    test('Condition 3: Backend returns 403 Forbidden returns specific bus not linked error', () async {
      final client = MockClient((request) async {
        return http.Response(
          jsonEncode({'detail': 'This bus is not linked to your account.'}),
          403,
          headers: {'content-type': 'application/json'},
        );
      });

      final service = VoiceAssistantService(httpClient: client);

      // English
      final enResponse = await service.handleQuery(
        recognizedText: 'where is the bus',
        busId: 'bus_999',
      );
      expect(enResponse, 'This bus is not linked to your account.');

      // Tamil
      final taResponse = await service.handleQuery(
        recognizedText: 'பேருந்து எங்கே',
        busId: 'bus_999',
      );
      expect(taResponse, 'இந்த பேருந்து உங்கள் கணக்குடன் இணைக்கப்படவில்லை.');
    });

    // -------------------------------------------------------------
    // 4. NO LIVE LOCATION YET
    // -------------------------------------------------------------
    test('Condition 4a: Location endpoint returns landmark "location not available"', () async {
      final client = MockClient((request) async {
        return http.Response(
          jsonEncode({'nearest_landmark': 'location not available', 'distance_km': 0.0}),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final service = VoiceAssistantService(httpClient: client);

      // English
      final enResponse = await service.handleQuery(
        recognizedText: 'where is the bus',
        busId: 'bus_10',
      );
      expect(enResponse, 'The bus has not started sharing its live location yet. Please check back shortly.');

      // Tamil
      final taResponse = await service.handleQuery(
        recognizedText: 'பேருந்து எங்கே இருக்கு',
        busId: 'bus_10',
      );
      expect(taResponse, 'பேருந்து இன்னும் நேரலை இருப்பிடத்தைப் பகிரத் தொடங்கவில்லை. சிறிது நேரம் கழித்து மீண்டும் பார்க்கவும்.');
    });

    test('Condition 4b: Location endpoint returns 404 (no GPS records found)', () async {
      final client = MockClient((request) async {
        return http.Response(
          jsonEncode({'detail': 'No live location found for bus'}),
          404,
          headers: {'content-type': 'application/json'},
        );
      });

      final service = VoiceAssistantService(httpClient: client);

      final enResponse = await service.handleQuery(
        recognizedText: 'where is the bus',
        busId: 'bus_10',
      );
      expect(enResponse, 'The bus has not started sharing its live location yet. Please check back shortly.');
    });

    test('Condition 4c: ETA endpoint returns "Location not available"', () async {
      final client = MockClient((request) async {
        return http.Response(
          jsonEncode({'eta': 'Location not available', 'eta_minutes': 0, 'stops_away': -1}),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final service = VoiceAssistantService(httpClient: client);

      final enResponse = await service.handleQuery(
        recognizedText: 'when will the bus arrive',
        busId: 'bus_10',
      );
      expect(enResponse, 'The bus has not started sharing its live location yet. Please check back shortly.');
    });

    test('Condition 4d: Stops-away endpoint returns stops_away == -1', () async {
      final client = MockClient((request) async {
        return http.Response(
          jsonEncode({'stops_away': -1}),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final service = VoiceAssistantService(httpClient: client);

      final enResponse = await service.handleQuery(
        recognizedText: 'how many stops away',
        busId: 'bus_10',
      );
      expect(enResponse, 'The bus has not started sharing its live location yet. Please check back shortly.');
    });

    // -------------------------------------------------------------
    // 5. SERVER ERROR (500 / 502 / 503 / 504)
    // -------------------------------------------------------------
    test('Condition 5: Backend returns 500 Internal Server Error returns specific server error', () async {
      final client = MockClient((request) async {
        return http.Response(
          'Internal Server Error',
          500,
        );
      });

      final service = VoiceAssistantService(httpClient: client);

      // English
      final enResponse = await service.handleQuery(
        recognizedText: 'where is the bus',
        busId: 'bus_10',
      );
      expect(enResponse, 'The server encountered an error. Please try again in a few moments.');

      // Tamil
      final taResponse = await service.handleQuery(
        recognizedText: 'பேருந்து எங்கே இருக்கு',
        busId: 'bus_10',
      );
      expect(taResponse, 'சர்வரில் பிழை ஏற்பட்டது. சிறிது நேரம் கழித்து மீண்டும் முயற்சிக்கவும்.');
    });

    // -------------------------------------------------------------
    // SUCCESS & UNKNOWN INTENT FALLBACK
    // -------------------------------------------------------------
    test('Success: Returns location when bus has active GPS', () async {
      final client = MockClient((request) async {
        return http.Response(
          jsonEncode({'nearest_landmark': 'Anna Nagar Circle', 'distance_km': 0.4}),
          200,
          headers: {'content-type': 'application/json'},
        );
      });

      final service = VoiceAssistantService(httpClient: client);

      final enResponse = await service.handleQuery(
        recognizedText: 'where is the bus',
        busId: 'bus_10',
      );
      expect(enResponse, 'The bus is currently near Anna Nagar Circle.');

      final taResponse = await service.handleQuery(
        recognizedText: 'பேருந்து எங்கே இருக்கு',
        busId: 'bus_10',
      );
      expect(taResponse, 'பேருந்து தற்போது Anna Nagar Circle அருகில் உள்ளது.');
    });

    test('Fallback: Unknown intent returns tpl_fallback without hitting backend', () async {
      var backendHit = false;
      final client = MockClient((request) async {
        backendHit = true;
        return http.Response('{}', 200);
      });

      final service = VoiceAssistantService(httpClient: client);

      final enResponse = await service.handleQuery(
        recognizedText: 'play music now',
        busId: 'bus_10',
      );
      expect(backendHit, false);
      expect(enResponse, "Sorry, I didn't understand that. Try asking where the bus is, or when it will arrive.");
    });
  });
}
