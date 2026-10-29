import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:bustrack/services/api_client.dart';

void main() {
  group('ApiClient Error Mapping and Logic', () {
    test('successful GET request returns parsed JSON and sends Bearer token', () async {
      String? sentAuthHeader;

      final mockClient = MockClient((request) async {
        sentAuthHeader = request.headers['Authorization'];
        return http.Response(jsonEncode({'status': 'ok'}), 200, headers: {'content-type': 'application/json'});
      });

      final client = ApiClient(
        baseUrl: 'https://example.com',
        client: mockClient,
        tokenGetter: () => 'my-test-token',
      );

      final result = await client.get('/api/test');
      expect(result, isA<Map>());
      expect(result['status'], 'ok');
      expect(sentAuthHeader, 'Bearer my-test-token');
    });

    test('401 error calls onUnauthorized when logged in and throws unauthorized', () async {
      var logoutCalled = 0;

      final mockClient = MockClient((request) async {
        return http.Response(jsonEncode({'detail': 'Token expired'}), 401);
      });

      final client = ApiClient(
        baseUrl: 'https://example.com',
        client: mockClient,
        tokenGetter: () => 'valid-token',
        onUnauthorized: () => logoutCalled++,
      );

      expect(
        () => client.get('/api/parent/me'),
        throwsA(isA<ApiException>().having((e) => e.kind, 'kind', ApiExceptionKind.unauthorized)),
      );

      await Future.delayed(const Duration(milliseconds: 10));
      expect(logoutCalled, 1);
    });

    test('403 error maps to forbidden', () async {
      final mockClient = MockClient((request) async {
        return http.Response(jsonEncode({'detail': 'Forbidden bus access'}), 403);
      });

      final client = ApiClient(baseUrl: 'https://example.com', client: mockClient);

      expect(
        () => client.get('/api/parent/bus/123/route'),
        throwsA(isA<ApiException>().having((e) => e.kind, 'kind', ApiExceptionKind.forbidden)),
      );
    });

    test('404 error maps to notFound', () async {
      final mockClient = MockClient((request) async {
        return http.Response(jsonEncode({'detail': 'Not registered'}), 404);
      });

      final client = ApiClient(baseUrl: 'https://example.com', client: mockClient);

      expect(
        () => client.post('/api/parent/login', body: {'phone': '9999999999'}),
        throwsA(isA<ApiException>().having((e) => e.kind, 'kind', ApiExceptionKind.notFound)),
      );
    });

    test('429 error maps to tooManyAttempts', () async {
      final mockClient = MockClient((request) async {
        return http.Response(jsonEncode({'detail': 'Rate limited'}), 429);
      });

      final client = ApiClient(baseUrl: 'https://example.com', client: mockClient);

      expect(
        () => client.post('/api/parent/login', body: {'phone': '9999999999'}),
        throwsA(isA<ApiException>().having((e) => e.kind, 'kind', ApiExceptionKind.tooManyAttempts)),
      );
    });

    test('500 error maps to server', () async {
      final mockClient = MockClient((request) async {
        return http.Response(jsonEncode({'detail': 'Internal error'}), 500);
      });

      final client = ApiClient(baseUrl: 'https://example.com', client: mockClient);

      expect(
        () => client.get('/api/test'),
        throwsA(isA<ApiException>().having((e) => e.kind, 'kind', ApiExceptionKind.server)),
      );
    });

    test('automatic retry on network failure for GET requests', () async {
      var callCount = 0;
      final mockClient = MockClient((request) async {
        callCount++;
        if (callCount == 1) {
          throw http.ClientException('Network drop');
        }
        return http.Response(jsonEncode({'retry': 'success'}), 200);
      });

      final client = ApiClient(baseUrl: 'https://example.com', client: mockClient);

      final res = await client.get('/api/test');
      expect(callCount, 2);
      expect(res['retry'], 'success');
    });
  });
}
