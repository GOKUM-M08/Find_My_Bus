import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import '../screens/config.dart';

enum ApiExceptionKind {
  network,
  timeout,
  unauthorized,
  forbidden,
  notFound,
  tooManyAttempts,
  server,
}

class ApiException implements Exception {
  final ApiExceptionKind kind;
  final String message;
  final int? statusCode;

  const ApiException({
    required this.kind,
    required this.message,
    this.statusCode,
  });

  @override
  String toString() => 'ApiException($kind, status: $statusCode, message: $message)';
}

class ApiClient {
  final String baseUrl;
  final http.Client _client;
  String? Function()? tokenGetter;
  void Function()? onUnauthorized;

  static const Duration normalTimeout = Duration(seconds: 12);
  static const Duration loginTimeout = Duration(seconds: 45);

  ApiClient({
    String? baseUrl,
    http.Client? client,
    this.tokenGetter,
    this.onUnauthorized,
  })  : baseUrl = (baseUrl ?? kBackendBaseUrl).replaceAll(RegExp(r'/+$'), ''),
        _client = client ?? http.Client();

  Uri _buildUri(String path, [Map<String, dynamic>? queryParameters]) {
    final cleanPath = path.startsWith('/') ? path : '/$path';
    final fullUrl = '$baseUrl$cleanPath';
    final uri = Uri.parse(fullUrl);
    if (queryParameters != null && queryParameters.isNotEmpty) {
      return uri.replace(
        queryParameters: {
          ...uri.queryParameters,
          ...queryParameters.map((k, v) => MapEntry(k, v.toString())),
        },
      );
    }
    return uri;
  }

  Map<String, String> _buildHeaders({Map<String, String>? extra}) {
    final headers = <String, String>{
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    };
    final token = tokenGetter?.call();
    if (token != null && token.isNotEmpty) {
      headers['Authorization'] = 'Bearer $token';
    }
    if (extra != null) {
      headers.addAll(extra);
    }
    return headers;
  }

  Future<dynamic> get(
    String path, {
    Map<String, dynamic>? queryParameters,
    Duration? timeout,
  }) async {
    final uri = _buildUri(path, queryParameters);
    final duration = timeout ?? normalTimeout;

    try {
      return await _executeWithTimeout(
        () => _client.get(uri, headers: _buildHeaders()),
        duration: duration,
      );
    } on ApiException catch (e) {
      if (e.kind == ApiExceptionKind.network) {
        // One automatic retry for GET requests on network failure
        try {
          return await _executeWithTimeout(
            () => _client.get(uri, headers: _buildHeaders()),
            duration: duration,
          );
        } catch (_) {
          rethrow;
        }
      }
      rethrow;
    }
  }

  Future<dynamic> post(
    String path, {
    dynamic body,
    Map<String, dynamic>? queryParameters,
    Duration? timeout,
  }) async {
    final uri = _buildUri(path, queryParameters);
    final isLogin = path.contains('/login');
    final duration = timeout ?? (isLogin ? loginTimeout : normalTimeout);

    final encodedBody = body is String
        ? body
        : (body != null ? jsonEncode(body) : null);

    return _executeWithTimeout(
      () => _client.post(
        uri,
        headers: _buildHeaders(),
        body: encodedBody,
      ),
      duration: duration,
    );
  }

  Future<dynamic> _executeWithTimeout(
    Future<http.Response> Function() action, {
    required Duration duration,
  }) async {
    try {
      final response = await action().timeout(duration);
      return _handleResponse(response);
    } on TimeoutException {
      throw const ApiException(
        kind: ApiExceptionKind.timeout,
        message: 'The server is taking too long. Please try again.',
      );
    } on SocketException catch (e) {
      throw ApiException(
        kind: ApiExceptionKind.network,
        message: 'No internet connection. Please check and try again. (${e.message})',
      );
    } on http.ClientException catch (e) {
      throw ApiException(
        kind: ApiExceptionKind.network,
        message: 'Network error. Please check and try again. (${e.message})',
      );
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException(
        kind: ApiExceptionKind.network,
        message: 'Network request failed: $e',
      );
    }
  }

  dynamic _handleResponse(http.Response response) {
    final statusCode = response.statusCode;
    dynamic jsonBody;
    String detailMessage = '';

    if (response.body.isNotEmpty) {
      try {
        jsonBody = jsonDecode(response.body);
        if (jsonBody is Map && jsonBody.containsKey('detail')) {
          final detail = jsonBody['detail'];
          detailMessage = detail is String ? detail : jsonEncode(detail);
        } else if (jsonBody is Map && jsonBody.containsKey('message')) {
          detailMessage = jsonBody['message'].toString();
        }
      } catch (_) {
        detailMessage = response.body;
      }
    }

    if (statusCode >= 200 && statusCode < 300) {
      return jsonBody;
    }

    if (statusCode == 401) {
      // On a 401 for a logged-in request, tell the session controller to log out, once.
      if (tokenGetter?.call() != null) {
        onUnauthorized?.call();
      }
      throw ApiException(
        kind: ApiExceptionKind.unauthorized,
        message: detailMessage.isNotEmpty ? detailMessage : 'Please log in again.',
        statusCode: 401,
      );
    }

    if (statusCode == 403) {
      throw ApiException(
        kind: ApiExceptionKind.forbidden,
        message: detailMessage.isNotEmpty
            ? detailMessage
            : 'This bus is not linked to your account.',
        statusCode: 403,
      );
    }

    if (statusCode == 404) {
      throw ApiException(
        kind: ApiExceptionKind.notFound,
        message: detailMessage.isNotEmpty
            ? detailMessage
            : 'This number is not registered with the school.',
        statusCode: 404,
      );
    }

    if (statusCode == 429) {
      throw ApiException(
        kind: ApiExceptionKind.tooManyAttempts,
        message: detailMessage.isNotEmpty
            ? detailMessage
            : 'Too many wrong attempts. Please try again after 15 minutes.',
        statusCode: 429,
      );
    }

    if (statusCode >= 500) {
      throw ApiException(
        kind: ApiExceptionKind.server,
        message: detailMessage.isNotEmpty
            ? detailMessage
            : 'Something went wrong on our side. Please try again later.',
        statusCode: statusCode,
      );
    }

    // 400 or other 4xx errors
    throw ApiException(
      kind: ApiExceptionKind.server,
      message: detailMessage.isNotEmpty ? detailMessage : 'Request failed with status $statusCode',
      statusCode: statusCode,
    );
  }
}
