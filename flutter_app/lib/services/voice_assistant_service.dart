import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:flutter_tts/flutter_tts.dart';
import '../screens/config.dart';
import 'language_service.dart';
import 'session_store.dart';

enum BusIntent { location, eta, delay, stopsAway, unknown }

class VoiceApiException implements Exception {
  final int statusCode;
  final String message;
  VoiceApiException(this.statusCode, this.message);
  @override
  String toString() => 'VoiceApiException($statusCode, $message)';
}

class VoiceNoLocationException implements Exception {
  final String message;
  VoiceNoLocationException([this.message = 'No live location yet']);
  @override
  String toString() => 'VoiceNoLocationException: $message';
}

class IntentKeyword {
  final String keyword;
  final String lang; // 'ta' or 'en'
  const IntentKeyword(this.keyword, this.lang);
}

class VoiceAssistantService {
  final stt.SpeechToText _speech;
  final FlutterTts _tts;
  final LanguageService _langService;
  http.Client _httpClient;

  bool _speechEnabled = false;

  VoiceAssistantService({
    stt.SpeechToText? speech,
    FlutterTts? tts,
    LanguageService? langService,
    http.Client? httpClient,
  })  : _speech = speech ?? stt.SpeechToText(),
        _tts = tts ?? FlutterTts(),
        _langService = langService ?? LanguageService(),
        _httpClient = httpClient ?? http.Client();

  set httpClient(http.Client client) => _httpClient = client;

  /// Initialize STT & TTS. Call once before use.
  Future<bool> init() async {
    try {
      _speechEnabled = await _speech.initialize(
        onError: (e) => debugPrint('[STT Error] $e'),
        onStatus: (s) => debugPrint('[STT Status] $s'),
      );
      await _tts.setSpeechRate(0.45);
      await _tts.setVolume(1.0);
      await _tts.setPitch(1.0);
    } catch (e) {
      debugPrint('[VoiceAssistant Init Error] $e');
      _speechEnabled = false;
    }
    return _speechEnabled;
  }

  bool get isReady => _speechEnabled;
  bool get isListening => _speech.isListening;

  /// Listen to parent's speech for up to 8 seconds.
  /// STT locale is picked from the manual app toggle (ta_IN vs en_IN).
  Future<void> listen({
    required Function(String recognizedText) onResult,
    required Function() onListeningComplete,
  }) async {
    if (!_speechEnabled) {
      final initialized = await init();
      if (!initialized) return;
    }

    final localeId = _langService.sttLocaleId;
    debugPrint('[STT Listening] Manual STT Locale: $localeId');

    await _speech.listen(
      localeId: localeId,
      onResult: (result) {
        if (result.finalResult || result.recognizedWords.isNotEmpty) {
          onResult(result.recognizedWords);
        }
      },
      listenFor: const Duration(seconds: 8),
      pauseFor: const Duration(seconds: 3),
    );
  }

  Future<void> stopListening() async {
    await _speech.stop();
  }

  /// Auto-detect language of recognized string based on Tamil Unicode range \u0B80–\u0BFF.
  String detectResponseLanguage(String text) {
    final hasTamilChar = RegExp(r'[\u0B80-\u0BFF]').hasMatch(text);
    return hasTamilChar ? 'ta' : 'en';
  }

  /// Full voice pipeline: Recognized text -> intent & keyword language -> fallback Unicode -> backend query -> speak response.
  Future<String> handleQuery({
    required String recognizedText,
    required String busId,
    String? stopId,
  }) async {
    final (intent, matchedLang) = _matchIntent(recognizedText);
    final unicodeLang = detectResponseLanguage(recognizedText);

    // Primary signal: matched keyword language ('ta' or 'en').
    // Secondary signal: Tamil Unicode script detection.
    final responseLangCode = (matchedLang == 'ta' || unicodeLang == 'ta') ? 'ta' : 'en';

    debugPrint(
        '[Voice Assistant] Matched Intent: $intent, Matched Lang: $matchedLang, Unicode Lang: $unicodeLang => Response Lang: $responseLangCode for "$recognizedText"');

    final responseText = await _resolveIntent(
      intent: intent,
      busId: busId,
      stopId: stopId,
      langCode: responseLangCode,
    );
    await speak(responseText, langCode: responseLangCode);
    return responseText;
  }

  // ---------------- Intent Keyword Definitions ----------------
  static const locationKeywords = [
    // English
    IntentKeyword('where', 'en'),
    IntentKeyword('location', 'en'),
    IntentKeyword('places', 'en'),
    IntentKeyword('where is', 'en'),
    IntentKeyword('where is the bus', 'en'),
    IntentKeyword('current location', 'en'),
    IntentKeyword('find the bus', 'en'),
    IntentKeyword('track the bus', 'en'),
    IntentKeyword('bus position', 'en'),
    IntentKeyword('which area', 'en'),
    IntentKeyword('near which stop', 'en'),
    // Tanglish
    IntentKeyword('bus enga', 'ta'),
    IntentKeyword('bus enga irukku', 'ta'),
    IntentKeyword('engirukku', 'ta'),
    IntentKeyword('எங்க இருக்கு bus', 'ta'),
    IntentKeyword('bus location enna', 'ta'),
    // Tamil script
    IntentKeyword('எங்கே', 'ta'),
    IntentKeyword('எங்க இருக்கு', 'ta'),
    IntentKeyword('இடம்', 'ta'),
    IntentKeyword('எங்கே இருக்கு', 'ta'),
    IntentKeyword('எங்க', 'ta'),
    IntentKeyword('பேருந்து எங்கே', 'ta'),
    IntentKeyword('இப்போது எங்கே', 'ta'),
  ];

  static const etaKeywords = [
    // English
    IntentKeyword('when will', 'en'),
    IntentKeyword('eta', 'en'),
    IntentKeyword('how long', 'en'),
    IntentKeyword('arrival', 'en'),
    IntentKeyword('when is the bus coming', 'en'),
    IntentKeyword('when does it arrive', 'en'),
    IntentKeyword('how much time', 'en'),
    IntentKeyword('what time will it come', 'en'),
    IntentKeyword('will it reach soon', 'en'),
    // Tanglish
    IntentKeyword('epo varum', 'ta'),
    IntentKeyword('eppo varum', 'ta'),
    IntentKeyword('evlo neram', 'ta'),
    IntentKeyword('epo vandhu serum', 'ta'),
    // Tamil script
    IntentKeyword('எப்போ வரும்', 'ta'),
    IntentKeyword('எப்போது வரும்', 'ta'),
    IntentKeyword('எவ்வளவு நேரம்', 'ta'),
    IntentKeyword('நேரம்', 'ta'),
    IntentKeyword('எப்போது வந்து சேரும்', 'ta'),
    IntentKeyword('இன்னும் எவ்வளவு நேரம்', 'ta'),
  ];

  static const delayKeywords = [
    // English
    IntentKeyword('late', 'en'),
    IntentKeyword('delay', 'en'),
    IntentKeyword('delayed', 'en'),
    IntentKeyword('on time', 'en'),
    IntentKeyword('running behind', 'en'),
    IntentKeyword('running behind schedule', 'en'),
    IntentKeyword('is it late today', 'en'),
    IntentKeyword('bus running late', 'en'),
    IntentKeyword('any delay', 'en'),
    // Tanglish
    IntentKeyword('thamathama', 'ta'),
    IntentKeyword('thamathamaga irukka', 'ta'),
    IntentKeyword('late ah irukka', 'ta'),
    IntentKeyword('correct time la varuma', 'ta'),
    // Tamil script
    IntentKeyword('தாமதம', 'ta'),
    IntentKeyword('தாமதம்', 'ta'),
    IntentKeyword('லேட்', 'ta'),
    IntentKeyword('தாமதமா', 'ta'),
    IntentKeyword('தாமதமாக இருக்கா', 'ta'),
    IntentKeyword('சரியான நேரத்தில் வருமா', 'ta'),
  ];

  static const stopsAwayKeywords = [
    // English
    IntentKeyword('how many stops', 'en'),
    IntentKeyword('stops away', 'en'),
    IntentKeyword('how far', 'en'),
    IntentKeyword('how many stops left', 'en'),
    IntentKeyword('distance to my stop', 'en'),
    IntentKeyword('how far is the bus from my stop', 'en'),
    IntentKeyword('stops remaining', 'en'),
    // Tanglish
    IntentKeyword('ethana stop', 'ta'),
    IntentKeyword('evlo stop irukku', 'ta'),
    IntentKeyword('nu stop dhaan irukku', 'ta'),
    // Tamil script
    IntentKeyword('எத்தனை stop', 'ta'),
    IntentKeyword('எத்தனை நிறுத்தம்', 'ta'),
    IntentKeyword('எத்தனை ஸ்டாப்', 'ta'),
    IntentKeyword('நிறுத்தங்கள்', 'ta'),
    IntentKeyword('எத்தனை நிறுத்தங்கள் தள்ளி', 'ta'),
    IntentKeyword('இன்னும் எத்தனை நிறுத்தம்', 'ta'),
  ];

  // ---------------- Intent Matching ----------------
  (BusIntent, String?) _matchIntent(String text) {
    final t = text.toLowerCase().trim();

    IntentKeyword? findMatch(List<IntentKeyword> keywords) {
      for (final k in keywords) {
        if (t.contains(k.keyword.toLowerCase())) {
          return k;
        }
      }
      return null;
    }

    final stopsMatch = findMatch(stopsAwayKeywords);
    if (stopsMatch != null) return (BusIntent.stopsAway, stopsMatch.lang);

    final delayMatch = findMatch(delayKeywords);
    if (delayMatch != null) return (BusIntent.delay, delayMatch.lang);

    final etaMatch = findMatch(etaKeywords);
    if (etaMatch != null) return (BusIntent.eta, etaMatch.lang);

    final locMatch = findMatch(locationKeywords);
    if (locMatch != null) return (BusIntent.location, locMatch.lang);

    return (BusIntent.unknown, null);
  }

  // ---------------- Backend Resolution ----------------
  Future<String> _resolveIntent({
    required BusIntent intent,
    required String busId,
    String? stopId,
    required String langCode,
  }) async {
    try {
      final queryParams = stopId != null ? '?stop_id=$stopId' : '';
      switch (intent) {
        case BusIntent.location:
          final data = await _get('/api/parent/bus/$busId/location');
          final landmark = data['nearest_landmark'] ?? data['stop_name'];
          if (landmark == null ||
              landmark.toString().trim().isEmpty ||
              landmark.toString().toLowerCase() == 'location not available' ||
              landmark.toString().toLowerCase() == 'unknown location') {
            throw VoiceNoLocationException('Bus location not available');
          }
          return _template('tpl_location', {'place': landmark.toString()}, langCode: langCode);

        case BusIntent.eta:
          final data = await _get('/api/parent/bus/$busId/eta$queryParams');
          final eta = data['eta']?.toString().toLowerCase() ?? '';
          final minutes = data['eta_minutes'] ?? 0;
          final stopsAway = data['stops_away'] ?? 0;
          if (eta.contains('not available') || (minutes == 0 && stopsAway < 0)) {
            throw VoiceNoLocationException('ETA location not available');
          }
          return _template('tpl_eta', {'minutes': '$minutes'}, langCode: langCode);

        case BusIntent.delay:
          final data = await _get('/api/parent/bus/$busId/status');
          final isLate = data['is_late'] == true;
          final delayMins = data['delay_minutes'] ?? 0;
          return isLate
              ? _template('tpl_delayed', {'minutes': '$delayMins'}, langCode: langCode)
              : _template('tpl_onTime', {}, langCode: langCode);

        case BusIntent.stopsAway:
          final data = await _get('/api/parent/bus/$busId/stops-away$queryParams');
          final count = data['stops_away'] ?? 0;
          if (count < 0) {
            throw VoiceNoLocationException('Stops away not available');
          }
          return _template('tpl_stopsAway', {'count': '$count'}, langCode: langCode);

        case BusIntent.unknown:
          return _template('tpl_fallback', {}, langCode: langCode);
      }
    } on VoiceNoLocationException catch (e) {
      debugPrint('[Voice Assistant No Location] $e');
      return _template('tpl_voice_no_location', {}, langCode: langCode);
    } on VoiceApiException catch (e) {
      debugPrint('[Voice Assistant API Error] ${e.statusCode}: ${e.message}');
      if (e.statusCode == 401) {
        return _template('tpl_voice_unauthorized', {}, langCode: langCode);
      } else if (e.statusCode == 403) {
        return _template('tpl_voice_forbidden', {}, langCode: langCode);
      } else {
        return _template('tpl_voice_server_error', {}, langCode: langCode);
      }
    } catch (e) {
      debugPrint('[Voice Assistant Query Error] $e');
      final errStr = e.toString().toLowerCase();
      if (errStr.contains('socket') ||
          errStr.contains('clientexception') ||
          errStr.contains('network') ||
          errStr.contains('timeout') ||
          errStr.contains('failed host lookup') ||
          errStr.contains('connection refused') ||
          errStr.contains('connection reset') ||
          errStr.contains('connection closed') ||
          errStr.contains('os error')) {
        return _template('tpl_voice_no_internet', {}, langCode: langCode);
      }
      return _template('tpl_voice_server_error', {}, langCode: langCode);
    }
  }

  Future<Map<String, dynamic>> _get(String path) async {
    final token = await SessionStore.instance.getToken();
    if (token == null || token.isEmpty) {
      throw VoiceApiException(401, 'Unauthorized: No token saved');
    }

    final url = Uri.parse('$kBackendBaseUrl$path');
    debugPrint('[Voice Assistant GET] $url');
    final headers = <String, String>{
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $token',
    };
    final res = await _httpClient.get(url, headers: headers).timeout(const Duration(seconds: 8));
    if (res.statusCode == 401) {
      throw VoiceApiException(401, 'Unauthorized');
    } else if (res.statusCode == 403) {
      throw VoiceApiException(403, 'Forbidden');
    } else if (res.statusCode == 404) {
      throw VoiceNoLocationException('Location not found');
    } else if (res.statusCode >= 500) {
      throw VoiceApiException(res.statusCode, 'Server error ${res.statusCode}');
    } else if (res.statusCode != 200) {
      throw VoiceApiException(res.statusCode, 'Backend error ${res.statusCode}');
    }
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  String _template(String key, Map<String, String> vars, {required String langCode}) {
    var text = _langService.getTextForLang(key, langCode);
    vars.forEach((k, v) => text = text.replaceAll('{$k}', v));
    return text;
  }

  Future<void> speak(String text, {String? langCode}) async {
    try {
      final ttsLang = (langCode ?? _langService.currentLanguage) == 'ta' ? 'ta-IN' : 'en-IN';
      debugPrint('[TTS Speaking] Language: $ttsLang, Text: $text');
      await _tts.setLanguage(ttsLang);
      await _tts.speak(text);
    } catch (e) {
      debugPrint('[TTS Error] $e');
    }
  }

  void dispose() {
    try {
      _speech.cancel();
      _tts.stop();
    } catch (_) {}
  }
}
