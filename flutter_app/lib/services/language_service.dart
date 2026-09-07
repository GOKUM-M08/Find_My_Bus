import 'package:flutter/material.dart';

enum VoiceLocale { tamil, english }

class LanguageService extends ChangeNotifier {
  static final LanguageService _instance = LanguageService._internal();
  factory LanguageService() => _instance;
  LanguageService._internal();

  String _currentLanguage = 'en'; // 'en' or 'ta'

  String get currentLanguage => _currentLanguage;
  bool get isTamil => _currentLanguage == 'ta';
  VoiceLocale get voiceLocale => isTamil ? VoiceLocale.tamil : VoiceLocale.english;

  String get sttLocaleId => isTamil ? 'ta_IN' : 'en_IN';
  String get ttsLanguage => isTamil ? 'ta-IN' : 'en-IN';

  void setLanguage(String langCode) {
    if (_currentLanguage != langCode) {
      _currentLanguage = langCode;
      notifyListeners();
    }
  }

  void toggleLanguage() {
    setLanguage(isTamil ? 'en' : 'ta');
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
      
      // Voice Assistant UI Keys
      'voice_assistant_title': 'Voice Assistant',
      'voice_assistant_subtitle': 'Ask about location, ETA, delays, or stops away',
      'tap_to_speak': 'Tap microphone to speak',
      'listening': 'Listening...',
      'processing': 'Processing query...',
      'speaking': 'Speaking response...',
      'try_asking': 'Try asking:',
      'example_location': '• "Where is the bus right now?"',
      'example_eta': '• "When will the bus arrive?"',
      'example_delay': '• "Is the bus running late?"',
      'example_stops': '• "How many stops away is the bus?"',
      'mic_permission_denied': 'Microphone permission denied. Please allow microphone access in settings.',
      
      // Stop Selection & Notification UI Keys
      'select_stop_notify': 'Select Stop for Notifications',
      'select_stop_subtitle': 'Choose your stop to receive 2-stops-away alert',
      'stop_notif_active': 'Alerts active for this stop',
      'notification_stop_set': 'Alerts active for {stop}',
      'tap_to_receive_alerts': 'Tap bell to receive alerts for this stop',
      'subscribed_to_stop': 'Subscribed to notifications for {stop}',
      'unsubscribed_from_stop': 'Changed notification stop to {stop}',
      'no_stop_selected': 'No stop selected for notifications yet',
      'stop_notifications_label': 'Notification Stop',
      
      // Templates
      'tpl_location': 'The bus is currently near {place}.',
      'tpl_eta': 'The bus will arrive in about {minutes} minutes.',
      'tpl_delayed': 'The bus is running about {minutes} minutes late.',
      'tpl_onTime': 'The bus is on time.',
      'tpl_stopsAway': 'The bus is {count} stops away.',
      'tpl_fallback': "Sorry, I didn't understand that. Try asking where the bus is, or when it will arrive.",
      'tpl_error': 'Sorry, I could not fetch the bus details right now. Please try again.',
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
      
      // Voice Assistant UI Keys
      'voice_assistant_title': 'குரல் உதவியாளர் (Voice Assistant)',
      'voice_assistant_subtitle': 'பேருந்தின் இடம், எப்போது வரும், தாமதம் அல்லது நிறுத்தங்களைக் கேட்கலாம்',
      'tap_to_speak': 'பேச மைக்கை அழுத்தவும்',
      'listening': 'கேட்கிறது...',
      'processing': 'செயலாக்குகிறது...',
      'speaking': 'பதில் கூறுகிறது...',
      'try_asking': 'இப்படி கேட்கலாம்:',
      'example_location': '• "பேருந்து எங்கே இருக்கு?"',
      'example_eta': '• "பேருந்து எப்போது வரும்?"',
      'example_delay': '• "பேருந்து தாமதமா?"',
      'example_stops': '• "பேருந்து எத்தனை நிறுத்தம் தள்ளி உள்ளது?"',
      'mic_permission_denied': 'மைக் அணுகல் மறுக்கப்பட்டது. அமைப்புகளில் மைக் அணுகலை அனுமதிக்கவும்.',
      
      // Stop Selection & Notification UI Keys
      'select_stop_notify': 'அறிவிப்பிற்கான நிறுத்தத்தைத் தேர்வு செய்',
      'select_stop_subtitle': '2 நிறுத்தங்கள் முன்னதாக அறிவிப்பைப் பெற உங்கள் நிறுத்தத்தைத் தேர்வு செய்க',
      'stop_notif_active': 'இந்த நிறுத்தத்திற்கு அறிவிப்புகள் செயலில் உள்ளன',
      'notification_stop_set': '{stop} நிறுத்தத்திற்கு அறிவிப்புகள் செயலில் உள்ளன',
      'tap_to_receive_alerts': 'அறிவிப்புகளைப் பெற மணிக்கூடு பொத்தானைத் தட்டவும்',
      'subscribed_to_stop': '{stop} நிறுத்தத்திற்கான அறிவிப்புகள் இயக்கப்பட்டது',
      'unsubscribed_from_stop': 'அறிவிப்பு நிறுத்தம் {stop} என மாற்றப்பட்டது',
      'no_stop_selected': 'இன்னும் அறிவிப்பு நிறுத்தம் தேர்வு செய்யப்படவில்லை',
      'stop_notifications_label': 'அறிவிப்பு நிறுத்தம்',

      // Templates
      'tpl_location': 'பேருந்து தற்போது {place} அருகில் உள்ளது.',
      'tpl_eta': 'பேருந்து சுமார் {minutes} நிமிடங்களில் வரும்.',
      'tpl_delayed': 'பேருந்து சுமார் {minutes} நிமிடங்கள் தாமதமாக உள்ளது.',
      'tpl_onTime': 'பேருந்து சரியான நேரத்தில் உள்ளது.',
      'tpl_stopsAway': 'பேருந்து {count} நிறுத்தங்கள் தொலைவில் உள்ளது.',
      'tpl_fallback': 'மன்னிக்கவும், புரியவில்லை. பேருந்து எங்கே உள்ளது என்று அல்லது எப்போது வரும் என்று கேளுங்கள்.',
      'tpl_error': 'மன்னிக்கவும், தற்போது தகவலைப் பெற முடியவில்லை. மீண்டும் முயற்சிக்கவும்.',
    },
  };

  String getText(String key) {
    return _localizedValues[_currentLanguage]?[key] ??
        _localizedValues['en']?[key] ??
        key;
  }

  String getTextForLang(String key, String langCode) {
    return _localizedValues[langCode]?[key] ??
        _localizedValues['en']?[key] ??
        key;
  }
}
