import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'api_client.dart';
import 'notification_service.dart';

class StudentInfo {
  final String studentId;
  final String? studentName;
  final String? parentName;
  final String? schoolName;
  final String? schoolPhone;
  final String? busId;
  final String? busNumber;
  final String? busCode;
  final String? driverName;
  final String? stopId;
  final String? stopName;
  final String? stopExpectedTime;

  StudentInfo({
    required this.studentId,
    this.studentName,
    this.parentName,
    this.schoolName,
    this.schoolPhone,
    this.busId,
    this.busNumber,
    this.busCode,
    this.driverName,
    this.stopId,
    this.stopName,
    this.stopExpectedTime,
  });

  factory StudentInfo.fromJson(Map<String, dynamic> json) {
    return StudentInfo(
      studentId: (json['student_id'] ?? json['id'] ?? '').toString(),
      studentName: json['student_name']?.toString(),
      parentName: json['parent_name']?.toString(),
      schoolName: json['school_name']?.toString(),
      schoolPhone: json['school_phone']?.toString(),
      busId: json['bus_id']?.toString(),
      busNumber: json['bus_number']?.toString(),
      busCode: json['bus_code']?.toString(),
      driverName: json['driver_name']?.toString(),
      stopId: json['stop_id']?.toString(),
      stopName: json['stop_name']?.toString(),
      stopExpectedTime: json['stop_expected_time']?.toString(),
    );
  }

  Map<String, dynamic> toJson() => {
    'student_id': studentId,
    'student_name': studentName,
    'parent_name': parentName,
    'school_name': schoolName,
    'school_phone': schoolPhone,
    'bus_id': busId,
    'bus_number': busNumber,
    'bus_code': busCode,
    'driver_name': driverName,
    'stop_id': stopId,
    'stop_name': stopName,
    'stop_expected_time': stopExpectedTime,
  };
}

class ParentProfile {
  final String? phone;
  final List<StudentInfo> students;

  ParentProfile({
    this.phone,
    required this.students,
  });

  factory ParentProfile.fromJson(Map<String, dynamic> json) {
    final list = json['students'];
    final studentsList = <StudentInfo>[];
    if (list is List) {
      for (final item in list) {
        if (item is Map<String, dynamic>) {
          studentsList.add(StudentInfo.fromJson(item));
        } else if (item is Map) {
          studentsList.add(StudentInfo.fromJson(Map<String, dynamic>.from(item)));
        }
      }
    }
    return ParentProfile(
      phone: json['phone']?.toString(),
      students: studentsList,
    );
  }

  Map<String, dynamic> toJson() => {
    'phone': phone,
    'students': students.map((s) => s.toJson()).toList(),
  };
}

enum SessionStatus { loading, loggedOut, loggedIn }

class SessionState {
  final SessionStatus status;
  final ParentProfile? profile;
  final String? logoutReason;

  const SessionState._({
    required this.status,
    this.profile,
    this.logoutReason,
  });

  const SessionState.loading() : this._(status: SessionStatus.loading);

  const SessionState.loggedOut([String? reason])
      : this._(status: SessionStatus.loggedOut, logoutReason: reason);

  const SessionState.loggedIn(ParentProfile profile)
      : this._(status: SessionStatus.loggedIn, profile: profile);

  bool get isLoading => status == SessionStatus.loading;
  bool get isLoggedIn => status == SessionStatus.loggedIn;
  bool get isLoggedOut => status == SessionStatus.loggedOut;
}

class SessionStore {
  static SessionStore instance = SessionStore();

  final FlutterSecureStorage _storage;

  static const String _keyToken = 'parent_jwt_token';
  static const String _keyProfile = 'parent_profile_json';

  SessionStore({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  Future<void> saveSession({required String token, required ParentProfile profile}) async {
    await _storage.write(key: _keyToken, value: token);
    await _storage.write(key: _keyProfile, value: jsonEncode(profile.toJson()));
  }

  Future<void> saveProfile(ParentProfile profile) async {
    await _storage.write(key: _keyProfile, value: jsonEncode(profile.toJson()));
  }

  Future<String?> getToken() async {
    return await _storage.read(key: _keyToken);
  }

  Future<ParentProfile?> getProfile() async {
    final raw = await _storage.read(key: _keyProfile);
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        return ParentProfile.fromJson(decoded);
      } else if (decoded is Map) {
        return ParentProfile.fromJson(Map<String, dynamic>.from(decoded));
      }
    } catch (_) {}
    return null;
  }

  Future<void> clear() async {
    await _storage.delete(key: _keyToken);
    await _storage.delete(key: _keyProfile);
  }
}

class SessionController extends ChangeNotifier {
  final SessionStore _store;
  final ApiClient _apiClient;

  SessionState _state = const SessionState.loading();
  String? _token;
  bool _isOffline = false;

  SessionState get state => _state;
  bool get isLoading => _state.isLoading;
  bool get isLoggedIn => _state.isLoggedIn;
  ParentProfile? get profile => _state.profile;
  String? get token => _token;
  bool get isOffline => _isOffline;
  ApiClient get apiClient => _apiClient;

  SessionController({
    SessionStore? store,
    ApiClient? apiClient,
  })  : _store = store ?? SessionStore(),
        _apiClient = apiClient ?? ApiClient() {
    _apiClient.tokenGetter = () => _token;
    _apiClient.onUnauthorized = () {
      logout(reason: 'Please log in again');
    };
  }

  Future<void> restore() async {
    _state = const SessionState.loading();
    notifyListeners();

    try {
      final token = await _store.getToken();
      final profile = await _store.getProfile();

      if (token != null && token.isNotEmpty && profile != null) {
        _token = token;
        _state = SessionState.loggedIn(profile);
        notifyListeners();
        try {
          NotificationService().syncSubscriptions(profile.students);
        } catch (_) {}
      } else {
        _token = null;
        _state = const SessionState.loggedOut();
        notifyListeners();
      }
    } catch (_) {
      _token = null;
      _state = const SessionState.loggedOut();
      notifyListeners();
    }
  }

  Future<ParentProfile> login(String phone) async {
    final response = await _apiClient.post(
      '/api/parent/login',
      body: {'phone': phone},
    );

    if (response is Map) {
      final map = Map<String, dynamic>.from(response);
      final token = map['token']?.toString();
      if (token == null || token.isEmpty) {
        throw const ApiException(
          kind: ApiExceptionKind.server,
          message: 'Server returned missing token.',
        );
      }
      final profile = ParentProfile.fromJson(map);
      _token = token;
      await _store.saveSession(token: token, profile: profile);
      _state = SessionState.loggedIn(profile);
      _isOffline = false;
      notifyListeners();
      try {
        await NotificationService().syncSubscriptions(profile.students);
      } catch (e) {
        debugPrint('[SessionController] syncSubscriptions failed on login: $e');
      }
      return profile;
    } else {
      throw const ApiException(
        kind: ApiExceptionKind.server,
        message: 'Invalid response from server.',
      );
    }
  }

  Future<void> refresh() async {
    if (_token == null) return;
    try {
      final response = await _apiClient.get('/api/parent/me');
      if (response is Map) {
        final profile = ParentProfile.fromJson(Map<String, dynamic>.from(response));
        await _store.saveProfile(profile);
        _state = SessionState.loggedIn(profile);
        _isOffline = false;
        notifyListeners();
        try {
          await NotificationService().syncSubscriptions(profile.students);
        } catch (e) {
          debugPrint('[SessionController] syncSubscriptions failed on refresh: $e');
        }
      }
    } on ApiException catch (e) {
      if (e.kind == ApiExceptionKind.unauthorized) {
        await logout(reason: 'Please log in again');
      } else if (e.kind == ApiExceptionKind.network || e.kind == ApiExceptionKind.timeout) {
        _isOffline = true;
        notifyListeners();
      }
    } catch (_) {
      _isOffline = true;
      notifyListeners();
    }
  }

  Future<void> logout({String? reason}) async {
    _token = null;
    await _store.clear();
    _state = SessionState.loggedOut(reason);
    _isOffline = false;
    notifyListeners();
  }
}
