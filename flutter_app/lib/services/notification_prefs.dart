import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'notification_service.dart';
import 'session_store.dart';

/// Manages phone-only notification preferences (enabled, language)
/// and triggers FCM topic synchronization when settings change.
class NotificationPrefs extends ChangeNotifier {
  static final NotificationPrefs _instance = NotificationPrefs._internal();
  factory NotificationPrefs() => _instance;
  NotificationPrefs._internal();

  static const String keyEnabled = 'notif_enabled';
  static const String keyLang = 'notif_lang';

  bool _enabled = true;
  String _language = 'ta';
  bool _initialized = false;

  bool get enabled => _enabled;
  String get language => _language;
  bool get isInitialized => _initialized;

  /// Loads persisted settings from SharedPreferences.
  Future<void> init() async {
    if (_initialized) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      _enabled = prefs.getBool(keyEnabled) ?? true;
      _language = prefs.getString(keyLang) ?? 'ta';
      _initialized = true;
      notifyListeners();
    } catch (e) {
      debugPrint('[NotificationPrefs init error] $e');
    }
  }

  /// Updates whether push notifications are enabled and resyncs topics.
  Future<void> setEnabled(bool value, {List<StudentInfo>? students}) async {
    _enabled = value;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(keyEnabled, value);
      await NotificationService().syncSubscriptions(students);
    } catch (e) {
      debugPrint('[NotificationPrefs setEnabled error] $e');
    }
  }

  /// Updates preferred notification language ('ta' or 'en') and resyncs topics.
  Future<void> setLanguage(String lang, {List<StudentInfo>? students}) async {
    if (lang != 'ta' && lang != 'en') return;
    _language = lang;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(keyLang, lang);
      await NotificationService().syncSubscriptions(students);
    } catch (e) {
      debugPrint('[NotificationPrefs setLanguage error] $e');
    }
  }
}
