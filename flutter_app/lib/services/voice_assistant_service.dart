import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:flutter_tts/flutter_tts.dart';
import '../screens/config.dart';
import 'language_service.dart';

enum BusIntent { location, eta, delay, stopsAway, unknown }

class VoiceAssistantService {
  final stt.SpeechToText _speech = stt.SpeechToText();
  final FlutterTts _tts = FlutterTts();
  final LanguageService _langService = LanguageService();

  bool _speechEnabled = false;

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

  /// Full voice pipeline: Recognized text -> auto-detect response language -> intent -> backend query -> format response -> speak.
  Future<String> handleQuery({
    required String recognizedText,
    required String busId,
    String? stopId,
  }) async {
    final responseLangCode = detectResponseLanguage(recognizedText);
    debugPrint('[Voice Assistant] Auto-detected response language: $responseLangCode for text: "$recognizedText"');

    final intent = _matchIntent(recognizedText);
    final responseText = await _resolveIntent(
      intent: intent,
      busId: busId,
      stopId: stopId,
      langCode: responseLangCode,
    );
    await speak(responseText, langCode: responseLangCode);
    return responseText;
  }

  // ---------------- Intent Matching ----------------
  BusIntent _matchIntent(String text) {
    final t = text.toLowerCase().trim();

    const locationKeywords = [
      'where', 'location', 'bus enga', 'engirukku', 'எங்கே', 'எங்க இருக்கு',
      'இடம்', 'எங்கே இருக்கு', 'எங்க', 'places'
    ];
    const etaKeywords = [
      'when will', 'eta', 'how long', 'epo varum', 'எப்போ வரும்', 'எப்போது வரும்',
      'எவ்வளவு நேரம்', 'arrival', 'நேரம்'
    ];
    const delayKeywords = [
      'late', 'delay', 'delayed', 'thamathama', 'தாமதம', 'தாமதம்', 'லேட்',
      'தாமதமா', 'on time'
    ];
    const stopsAwayKeywords = [
      'how many stops', 'stops away', 'how far', 'எத்தனை stop', 'எத்தனை நிறுத்தம்',
      'எத்தனை ஸ்டாப்', 'நிறுத்தங்கள்'
    ];

    bool has(List<String> keywords) => keywords.any((k) => t.contains(k));

    if (has(stopsAwayKeywords)) return BusIntent.stopsAway;
    if (has(delayKeywords)) return BusIntent.delay;
    if (has(etaKeywords)) return BusIntent.eta;
    if (has(locationKeywords)) return BusIntent.location;
    return BusIntent.unknown;
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
          final data = await _get('/buses/$busId/location');
          final landmark = data['nearest_landmark'] ?? data['stop_name'] ?? 'Main Gate';
          return _template('tpl_location', {'place': landmark}, langCode: langCode);

        case BusIntent.eta:
          final data = await _get('/buses/$busId/eta$queryParams');
          final minutes = data['eta_minutes'] ?? 0;
          return _template('tpl_eta', {'minutes': '$minutes'}, langCode: langCode);

        case BusIntent.delay:
          final data = await _get('/buses/$busId/status');
          final isLate = data['is_late'] == true;
          final delayMins = data['delay_minutes'] ?? 0;
          return isLate
              ? _template('tpl_delayed', {'minutes': '$delayMins'}, langCode: langCode)
              : _template('tpl_onTime', {}, langCode: langCode);

        case BusIntent.stopsAway:
          final data = await _get('/buses/$busId/stops-away$queryParams');
          final count = data['stops_away'] ?? 0;
          return _template('tpl_stopsAway', {'count': '$count'}, langCode: langCode);

        case BusIntent.unknown:
          return _template('tpl_fallback', {}, langCode: langCode);
      }
    } catch (e) {
      debugPrint('[Voice Assistant Query Error] $e');
      return _template('tpl_error', {}, langCode: langCode);
    }
  }

  Future<Map<String, dynamic>> _get(String path) async {
    final url = Uri.parse('$kBackendBaseUrl$path');
    debugPrint('[Voice Assistant GET] $url');
    final res = await http.get(url).timeout(const Duration(seconds: 8));
    if (res.statusCode != 200) {
      throw Exception('Backend error ${res.statusCode}');
    }
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  String _template(String key, Map<String, String> vars, {required String langCode}) {
    var text = _langService.getTextForLang(key, langCode);
    vars.forEach((k, v) => text = text.replaceAll('{$k}', v));
    return text;
  }

  Future<void> speak(String text, {String? langCode}) async {
    final ttsLang = (langCode ?? _langService.currentLanguage) == 'ta' ? 'ta-IN' : 'en-IN';
    debugPrint('[TTS Speaking] Language: $ttsLang, Text: $text');
    await _tts.setLanguage(ttsLang);
    await _tts.speak(text);
  }

  void dispose() {
    _speech.cancel();
    _tts.stop();
  }
}
