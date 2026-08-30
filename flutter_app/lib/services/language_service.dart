import 'package:flutter/material.dart';

class LanguageService extends ChangeNotifier {
  static final LanguageService _instance = LanguageService._internal();
  factory LanguageService() => _instance;
  LanguageService._internal();

  String _currentLanguage = 'en'; // 'en' or 'ta'

  String get currentLanguage => _currentLanguage;
  bool get isTamil => _currentLanguage == 'ta';

  void setLanguage(String langCode) {
    if (_currentLanguage != langCode) {
      _currentLanguage = langCode;
      notifyListeners();
    }
  }

  // Dictionary for English and Tamil strings
  static const Map<String, Map<String, String>> _localizedValues = {
    'en': {
      'app_title': 'Find My Bus',
      'app_subtitle': 'Find My Bus - Easy Tracking',
      'search_hint': 'Bus No., school or college',
      'search_subtext': 'Search your bus number or school to see it live.',
      'browse_buses': 'BROWSE BUSES',
      'no_buses': 'No buses registered yet',
      'admin_login': 'Admin Login',
      'driver_login': 'Driver Login',
      'menu': 'MENU',
      'my_profile': 'My Profile',
      'language': 'Language',
      'faq_help': 'FAQ & Help',
      'suggest_feature': 'Suggest a Feature',
      'about_app': 'About Find My Bus',
      'share_app': 'Share App',
      'privacy_policy': 'Privacy Policy',
      'theme_settings': 'Theme & Settings',
      'support': 'Support',
      'phone_support': 'Phone Support',
      'email_support': 'Email Support',
      'select_language': 'Select Language / மொழியைத் தேர்ந்தெடுக்கவும்',
      'english': 'English',
      'tamil': 'தமிழ் (Tamil)',
      'close': 'Close',
      'cancel': 'Cancel',
      'submit': 'Submit',
      'save': 'Save',
      'live': 'LIVE',
      'offline': 'Offline',
      'school': 'School',
      'bus': 'Bus',
      'tap_to_see_buses': 'School — tap to see its buses',
      'no_search_results': 'No buses or schools matched that search.',
    },
    'ta': {
      'app_title': 'என் பேருந்து (Find My Bus)',
      'app_subtitle': 'என் பேருந்து - சுலபமான நேரலை கண்காணிப்பு',
      'search_hint': 'பேருந்து எண், பள்ளி அல்லது கல்லூரி',
      'search_subtext': 'நேரலையில் பார்க்க உங்கள் பேருந்து எண் அல்லது பள்ளியைத் தேடுங்கள்.',
      'browse_buses': 'பேருந்துகளைப் பார்க்கவும்',
      'no_buses': 'இன்னும் பேருந்துகள் எதுவும் பதிவு செய்யப்படவில்லை',
      'admin_login': 'நிர்வாகி உள்நுழைவு',
      'driver_login': 'ஓட்டுநர் உள்நுழைவு',
      'menu': 'முதன்மை மெனு',
      'my_profile': 'என் சுயவிவரம்',
      'language': 'மொழி (Language)',
      'faq_help': 'கேள்விகள் & உதவி (FAQ)',
      'suggest_feature': 'அம்சத்தைப் பரிந்துரைக்க',
      'about_app': 'பயன்பாட்டைப் பற்றி',
      'share_app': 'செயலியைப் பகிரவும்',
      'privacy_policy': 'தனியுரிமைக் கொள்கை',
      'theme_settings': 'தீம் & அமைப்புகள்',
      'support': 'உதவி / ஆதரவு',
      'phone_support': 'தொலைபேசி உதவி',
      'email_support': 'மின்னஞ்சல் உதவி',
      'select_language': 'மொழியைத் தேர்ந்தெடுக்கவும் (Select Language)',
      'english': 'English (ஆங்கிலம்)',
      'tamil': 'தமிழ் (Tamil)',
      'close': 'மூடு',
      'cancel': 'ரத்து செய்',
      'submit': 'சமர்ப்பி',
      'save': 'சேமி',
      'live': 'நேரலை',
      'offline': 'ஆஃப்லைன்',
      'school': 'பள்ளி',
      'bus': 'பேருந்து',
      'tap_to_see_buses': 'பள்ளி — பேருந்துகளைப் பார்க்க தட்டவும்',
      'no_search_results': 'எந்த பேருந்தும் அல்லது பள்ளியும் கிடைக்கவில்லை.',
    },
  };

  String getText(String key) {
    return _localizedValues[_currentLanguage]?[key] ??
        _localizedValues['en']?[key] ??
        key;
  }
}
