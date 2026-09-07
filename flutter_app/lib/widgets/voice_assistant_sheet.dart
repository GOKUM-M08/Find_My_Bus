import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import '../services/language_service.dart';
import '../services/voice_assistant_service.dart';
import '../services/notification_service.dart';

const Color PRIMARY_BLUE = Color(0xFF0052CC);
const Color SECONDARY_BLUE = Color(0xFF1E6BFF);
const Color LIGHT_BLUE = Color(0xFFE8F0FE);
const Color BACKGROUND_BLUE = Color(0xFFF7F9FC);

class VoiceAssistantSheet extends StatefulWidget {
  final String busId;
  final String busNumber;
  final String? stopId;

  const VoiceAssistantSheet({
    super.key,
    required this.busId,
    required this.busNumber,
    this.stopId,
  });

  static void show(BuildContext context, {
    required String busId,
    required String busNumber,
    String? stopId,
  }) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => VoiceAssistantSheet(
        busId: busId,
        busNumber: busNumber,
        stopId: stopId,
      ),
    );
  }

  @override
  State<VoiceAssistantSheet> createState() => _VoiceAssistantSheetState();
}

class _VoiceAssistantSheetState extends State<VoiceAssistantSheet>
    with SingleTickerProviderStateMixin {
  final VoiceAssistantService _voiceService = VoiceAssistantService();
  final LanguageService _langService = LanguageService();

  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  String _statusState = 'idle'; // 'idle', 'listening', 'processing', 'speaking'
  String _queryText = '';
  String _responseText = '';
  bool _initializing = true;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.22).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _langService.addListener(_onLanguageChanged);
    _initVoice();
  }

  @override
  void dispose() {
    _langService.removeListener(_onLanguageChanged);
    _pulseController.dispose();
    _voiceService.dispose();
    super.dispose();
  }

  void _onLanguageChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _initVoice() async {
    await _voiceService.init();
    if (mounted) {
      setState(() => _initializing = false);
    }
  }

  Future<void> _startListening() async {
    final micStatus = await Permission.microphone.request();
    if (micStatus.isDenied || micStatus.isPermanentlyDenied) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_langService.getText('mic_permission_denied')),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }

    setState(() {
      _statusState = 'listening';
      _queryText = '';
      _responseText = '';
    });
    _pulseController.repeat(reverse: true);

    await _voiceService.listen(
      onResult: (recognized) {
        if (!mounted) return;
        setState(() {
          _queryText = recognized;
        });
        _processQuery(recognized);
      },
      onListeningComplete: () {
        if (mounted && _statusState == 'listening') {
          _pulseController.stop();
          _pulseController.reset();
          if (_queryText.isEmpty) {
            setState(() => _statusState = 'idle');
          }
        }
      },
    );
  }

  Future<void> _processQuery(String text) async {
    if (text.trim().isEmpty) return;

    _pulseController.stop();
    _pulseController.reset();
    await _voiceService.stopListening();

    setState(() {
      _statusState = 'processing';
    });

    final effectiveStopId = widget.stopId ?? await NotificationService().getSelectedStopId(widget.busId);

    final reply = await _voiceService.handleQuery(
      recognizedText: text,
      busId: widget.busId,
      stopId: effectiveStopId,
    );

    if (mounted) {
      setState(() {
        _responseText = reply;
        _statusState = 'speaking';
      });
    }
  }

  void _triggerSuggestion(String sampleQuery) {
    setState(() {
      _queryText = sampleQuery;
    });
    _processQuery(sampleQuery);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.only(
        top: 16,
        left: 20,
        right: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag handle
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey.shade300,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 16),

          // Header Row: Title & Language Toggle
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: LIGHT_BLUE,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.mic, color: PRIMARY_BLUE, size: 22),
                  ),
                  const SizedBox(width: 10),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _langService.getText('voice_assistant_title'),
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                          color: PRIMARY_BLUE,
                        ),
                      ),
                      Text(
                        'Bus #${widget.busNumber}',
                        style: const TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                    ],
                  ),
                ],
              ),

              // Tamil / English Toggle Switch
              InkWell(
                onTap: () => _langService.toggleLanguage(),
                borderRadius: BorderRadius.circular(20),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: LIGHT_BLUE,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: SECONDARY_BLUE.withOpacity(0.3)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.language, size: 16, color: PRIMARY_BLUE),
                      const SizedBox(width: 6),
                      Text(
                        _langService.isTamil ? 'தமிழ்' : 'English',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                          color: PRIMARY_BLUE,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 20),

          // Recognized Query Bubble
          if (_queryText.isNotEmpty)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: LIGHT_BLUE.withOpacity(0.5),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  const Icon(Icons.record_voice_over, size: 18, color: SECONDARY_BLUE),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '"$_queryText"',
                      style: const TextStyle(
                        fontStyle: FontStyle.italic,
                        fontWeight: FontWeight.w600,
                        color: PRIMARY_BLUE,
                      ),
                    ),
                  ),
                ],
              ),
            ),

          // Response Bubble
          if (_responseText.isNotEmpty)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 16),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [PRIMARY_BLUE, SECONDARY_BLUE],
                ),
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: PRIMARY_BLUE.withOpacity(0.25),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.directions_bus, color: Colors.white, size: 18),
                          SizedBox(width: 6),
                          Text(
                            'Bus Track Voice',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                      IconButton(
                        icon: const Icon(Icons.volume_up_rounded, color: Colors.white, size: 20),
                        constraints: const BoxConstraints(),
                        padding: EdgeInsets.zero,
                        onPressed: () => _voiceService.speak(_responseText),
                        tooltip: 'Replay audio',
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _responseText,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      height: 1.35,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),

          // Mic Button Section
          const SizedBox(height: 8),
          ScaleTransition(
            scale: _pulseAnimation,
            child: Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _statusState == 'listening'
                    ? Colors.red.shade600
                    : SECONDARY_BLUE,
                boxShadow: [
                  BoxShadow(
                    color: (_statusState == 'listening'
                            ? Colors.red
                            : SECONDARY_BLUE)
                        .withOpacity(0.4),
                    blurRadius: 16,
                    spreadRadius: 2,
                  )
                ],
              ),
              child: IconButton(
                onPressed: _initializing
                    ? null
                    : () {
                        if (_statusState == 'listening') {
                          _voiceService.stopListening();
                          _pulseController.stop();
                          _pulseController.reset();
                          setState(() => _statusState = 'idle');
                        } else {
                          _startListening();
                        }
                      },
                icon: Icon(
                  _statusState == 'listening'
                      ? Icons.mic
                      : _statusState == 'processing'
                          ? Icons.hourglass_top_rounded
                          : Icons.mic_none_rounded,
                  color: Colors.white,
                  size: 34,
                ),
              ),
            ),
          ),

          const SizedBox(height: 12),
          Text(
            _statusState == 'listening'
                ? _langService.getText('listening')
                : _statusState == 'processing'
                    ? _langService.getText('processing')
                    : _statusState == 'speaking'
                        ? _langService.getText('speaking')
                        : _langService.getText('tap_to_speak'),
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: _statusState == 'listening' ? Colors.red : Colors.grey.shade700,
            ),
          ),

          const SizedBox(height: 20),

          // Suggestion Chips (Common Intents)
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _langService.getText('try_asking'),
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _SuggestionChip(
                    label: _langService.isTamil ? 'எங்கே இருக்கு?' : 'Where is the bus?',
                    onTap: () => _triggerSuggestion(
                      _langService.isTamil ? 'பேருந்து எங்கே இருக்கு' : 'Where is the bus right now',
                    ),
                  ),
                  _SuggestionChip(
                    label: _langService.isTamil ? 'எப்போது வரும்?' : 'When will it arrive?',
                    onTap: () => _triggerSuggestion(
                      _langService.isTamil ? 'பேருந்து எப்போது வரும்' : 'When will the bus arrive',
                    ),
                  ),
                  _SuggestionChip(
                    label: _langService.isTamil ? 'தாமதமா?' : 'Is it late?',
                    onTap: () => _triggerSuggestion(
                      _langService.isTamil ? 'பேருந்து தாமதமா' : 'Is the bus running late',
                    ),
                  ),
                  _SuggestionChip(
                    label: _langService.isTamil ? 'எத்தனை நிறுத்தம்?' : 'How many stops away?',
                    onTap: () => _triggerSuggestion(
                      _langService.isTamil ? 'பேருந்து எத்தனை நிறுத்தம் தள்ளி உள்ளது' : 'How many stops away is the bus',
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SuggestionChip extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _SuggestionChip({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return ActionChip(
      backgroundColor: LIGHT_BLUE,
      side: BorderSide(color: SECONDARY_BLUE.withOpacity(0.3)),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      avatar: const Icon(Icons.help_outline, size: 14, color: PRIMARY_BLUE),
      label: Text(
        label,
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: PRIMARY_BLUE,
        ),
      ),
      onPressed: onTap,
    );
  }
}
