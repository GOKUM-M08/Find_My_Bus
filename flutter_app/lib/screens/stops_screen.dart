import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'tracking_screen.dart';
import '../services/api_client.dart';
import '../services/language_service.dart';
import '../services/session_store.dart';
import '../widgets/voice_assistant_sheet.dart';

const Color PRIMARY_BLUE = Color(0xFF0052CC);
const Color SECONDARY_BLUE = Color(0xFF1E6BFF);
const Color LIGHT_BLUE = Color(0xFFE8F0FE);
const Color BACKGROUND_BLUE = Color(0xFFF7F9FC);

class StopsScreen extends StatefulWidget {
  final String busId;
  final String busNumber;
  final String schoolName;
  final String? studentStopId;

  const StopsScreen({
    super.key,
    required this.busId,
    required this.busNumber,
    required this.schoolName,
    this.studentStopId,
  });

  @override
  State<StopsScreen> createState() => _StopsScreenState();
}

class _StopsScreenState extends State<StopsScreen> with WidgetsBindingObserver {
  final languageService = LanguageService();

  List<Map<String, dynamic>> _stops = [];
  bool _loading = true;
  String? _errorMessage;
  int _currentStopIndex = -1;
  bool _busIsLive = false;
  bool _isReconnecting = false;
  String _tripDirection = 'morning';

  Timer? _pollTimer;
  int _pollIntervalSeconds = 5;
  bool _isScreenVisible = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    languageService.addListener(_onLanguageChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadInitialData();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    languageService.removeListener(_onLanguageChanged);
    _pollTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _isScreenVisible = true;
      _schedulePoll(immediate: true);
    } else if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      _isScreenVisible = false;
      _pollTimer?.cancel();
    }
  }

  void _onLanguageChanged() {
    if (mounted) setState(() {});
  }

  String _str(dynamic val) => val?.toString() ?? '';

  Future<void> _loadInitialData() async {
    if (!mounted) return;
    final session = context.read<SessionController>();
    final api = session.apiClient;

    setState(() {
      _loading = true;
      _errorMessage = null;
    });

    try {
      // 1. Fetch trip direction
      try {
        final dirRes = await api.get('/api/parent/bus/${widget.busId}/trip-direction');
        if (dirRes is Map && dirRes['trip_direction'] != null) {
          _tripDirection = dirRes['trip_direction'].toString();
        }
      } catch (_) {}

      // 2. Fetch route and stops
      final routeRes = await api.get('/api/parent/bus/${widget.busId}/route');
      List<Map<String, dynamic>> loadedStops = [];
      if (routeRes is List && routeRes.isNotEmpty) {
        final firstRoute = routeRes[0];
        if (firstRoute is Map && firstRoute['stops'] is List) {
          loadedStops = List<Map<String, dynamic>>.from(firstRoute['stops']);
        }
      }

      if (!mounted) return;
      setState(() {
        _stops = loadedStops;
        _loading = false;
        _isReconnecting = false;
        _pollIntervalSeconds = 5;
      });

      // 3. Immediately poll live location and start 5s loop
      await _pollLiveLocation();
      _schedulePoll();
    } on ApiException catch (e) {
      if (!mounted) return;
      if (e.kind == ApiExceptionKind.unauthorized) {
        session.logout(reason: 'Please log in again');
        return;
      } else if (e.kind == ApiExceptionKind.forbidden) {
        setState(() {
          _loading = false;
          _errorMessage = languageService.getText('bus_not_linked');
        });
        return;
      }
      setState(() {
        _loading = false;
        _isReconnecting = true;
      });
      _schedulePoll();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _isReconnecting = true;
      });
      _schedulePoll();
    }
  }

  void _schedulePoll({bool immediate = false}) {
    _pollTimer?.cancel();
    if (!_isScreenVisible || !mounted) return;

    if (immediate) {
      _pollLiveLocation();
    } else {
      _pollTimer = Timer(Duration(seconds: _pollIntervalSeconds), () async {
        await _pollLiveLocation();
        _schedulePoll();
      });
    }
  }

  Future<void> _pollLiveLocation() async {
    if (!mounted || !_isScreenVisible) return;
    final session = context.read<SessionController>();
    final api = session.apiClient;

    try {
      final locRes = await api.get('/api/parent/bus/${widget.busId}/live');

      if (!mounted) return;

      if (locRes == null || locRes is! Map) {
        setState(() {
          _busIsLive = false;
          _isReconnecting = false;
          _pollIntervalSeconds = 5;
        });
        return;
      }

      final rawTimestamp = locRes['timestamp'];
      bool isRecent = false;
      if (rawTimestamp != null) {
        final lastUpdate = DateTime.parse(rawTimestamp.toString()).toUtc();
        final secondsAgo = DateTime.now().toUtc().difference(lastUpdate).inSeconds;
        isRecent = secondsAgo < 60;
      }

      if (!isRecent) {
        setState(() {
          _busIsLive = false;
          _isReconnecting = false;
          _pollIntervalSeconds = 5;
        });
        return;
      }

      final busLat = (locRes['latitude'] as num?)?.toDouble() ?? 0.0;
      final busLon = (locRes['longitude'] as num?)?.toDouble() ?? 0.0;

      int nearestIndex = -1;
      if (_stops.isNotEmpty && busLat != 0.0 && busLon != 0.0) {
        double minDistance = double.infinity;
        for (int i = 0; i < _stops.length; i++) {
          final sLat = (_stops[i]['latitude'] as num?)?.toDouble() ?? 0.0;
          final sLon = (_stops[i]['longitude'] as num?)?.toDouble() ?? 0.0;
          final d = _haversine(busLat, busLon, sLat, sLon);
          if (d < minDistance) {
            minDistance = d;
            nearestIndex = i;
          }
        }
      }

      setState(() {
        _currentStopIndex = nearestIndex;
        _busIsLive = true;
        _isReconnecting = false;
        _pollIntervalSeconds = 5; // reset interval on successful poll
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      if (e.kind == ApiExceptionKind.unauthorized) {
        session.logout(reason: 'Please log in again');
        return;
      } else if (e.kind == ApiExceptionKind.forbidden) {
        setState(() {
          _errorMessage = languageService.getText('bus_not_linked');
        });
        return;
      }
      _handlePollBackoff();
    } catch (_) {
      _handlePollBackoff();
    }
  }

  void _handlePollBackoff() {
    if (!mounted) return;
    setState(() {
      _isReconnecting = true;
      // Exponential backoff: 5s -> 10s -> 20s -> 30s
      _pollIntervalSeconds = min(_pollIntervalSeconds * 2, 30);
    });
  }

  double _haversine(double lat1, double lon1, double lat2, double lon2) {
    const r = 6371.0;
    final dLat = (lat2 - lat1) * (pi / 180);
    final dLon = (lon2 - lon1) * (pi / 180);
    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(lat1 * (pi / 180)) * cos(lat2 * (pi / 180)) * sin(dLon / 2) * sin(dLon / 2);
    final c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return r * c;
  }

  void _viewOnMap({String? stopId}) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => TrackingScreen(
          busId: widget.busId,
          busNumber: widget.busNumber,
          stopId: stopId ?? widget.studentStopId,
        ),
      ),
    );
  }

  void _openVoiceAssistant() {
    VoiceAssistantSheet.show(
      context,
      busId: widget.busId,
      busNumber: widget.busNumber,
      stopId: widget.studentStopId,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: BACKGROUND_BLUE,
      appBar: AppBar(
        backgroundColor: PRIMARY_BLUE,
        foregroundColor: Colors.white,
        elevation: 4,
        title: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: Image.asset(
                'assets/icon/icon.png',
                width: 26,
                height: 26,
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => const Icon(
                  Icons.directions_bus_rounded,
                  color: Colors.white,
                  size: 24,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '${languageService.getText('bus')} ${widget.busNumber}',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
                  ),
                  if (widget.schoolName.isNotEmpty)
                    Text(
                      widget.schoolName,
                      style: const TextStyle(fontSize: 11, color: Colors.white70),
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: languageService.getText('voice_assistant_title'),
            icon: const Icon(Icons.mic_rounded),
            onPressed: _openVoiceAssistant,
          ),
          TextButton.icon(
            onPressed: () => languageService.toggleLanguage(),
            icon: const Icon(Icons.language, color: Colors.white, size: 18),
            label: Text(
              languageService.isTamil ? 'தமிழ்' : 'EN',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(color: PRIMARY_BLUE),
      );
    }

    if (_errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline_rounded, color: Colors.red, size: 48),
              const SizedBox(height: 12),
              Text(
                _errorMessage!,
                textAlign: TextAlign.center,
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
              ),
            ],
          ),
        ),
      );
    }

    if (_stops.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(
            languageService.isTamil
                ? 'இந்த பேருந்துக்கான நிறுத்தங்கள் அமைக்கப்படவில்லை.'
                : 'No stops have been set up for this bus yet.',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.grey),
          ),
        ),
      );
    }

    return Column(
      children: [
        // Reconnecting Banner
        if (_isReconnecting)
          Container(
            width: double.infinity,
            color: Colors.amber.shade700,
            padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  languageService.getText('reconnecting'),
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          )
        else if (_busIsLive)
          Container(
            width: double.infinity,
            color: Colors.green.shade50,
            padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 16),
            child: Row(
              children: [
                const Icon(Icons.circle, color: Colors.green, size: 10),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    languageService.isTamil
                        ? 'பேருந்து நேரலையில் உள்ளது'
                        : 'Bus is live — updated moments ago',
                    style: const TextStyle(
                      color: Colors.green,
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),

        _buildTripDirectionBanner(),

        // Stops Timeline List
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
            itemCount: _stops.length + 1,
            itemBuilder: (context, index) {
              if (index == 0) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12, top: 4),
                  child: Text(
                    '${_stops.length} ${languageService.isTamil ? "நிறுத்தங்கள் அமைக்கப்பட்ட பாதை" : "stops on this route."}',
                    style: const TextStyle(
                      color: Colors.grey,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                );
              }
              return _buildStopRow(index - 1);
            },
          ),
        ),

        _buildBottomBar(),
      ],
    );
  }

  Widget _buildStopRow(int index) {
    final stop = _stops[index];
    final stopId = _str(stop['id']);
    final isPassed = _currentStopIndex >= 0 && index < _currentStopIndex;
    final isCurrent = _currentStopIndex == index;
    final isStudentStop = widget.studentStopId != null &&
        widget.studentStopId!.isNotEmpty &&
        widget.studentStopId == stopId;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: isStudentStop ? LIGHT_BLUE : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isStudentStop ? PRIMARY_BLUE : Colors.grey.shade200,
          width: isStudentStop ? 2.0 : 1.0,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => _viewOnMap(stopId: stop['id']?.toString()),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                // Timeline indicator
                _buildStopIndicator(isPassed, isCurrent, isStudentStop),
                const SizedBox(width: 12),

                // Stop Name & Expected Time
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              stop['stop_name'] ?? '',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: (isCurrent || isStudentStop)
                                    ? FontWeight.bold
                                    : FontWeight.w600,
                                color: isPassed ? Colors.grey : const Color(0xFF0F172A),
                              ),
                            ),
                          ),
                          if (stop['expected_time'] != null)
                            Text(
                              _str(stop['expected_time']),
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: isPassed ? Colors.grey : PRIMARY_BLUE,
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 4),

                      // Student stop badge / Live position text
                      if (isStudentStop)
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: PRIMARY_BLUE,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(
                                    Icons.notifications_active_rounded,
                                    size: 12,
                                    color: Colors.white,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    '${languageService.getText('your_stop')} • ${languageService.getText('alerts_on')}',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 11,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        )
                      else if (isCurrent)
                        Text(
                          languageService.isTamil ? 'பேருந்து இங்கு உள்ளது' : 'Bus is near here',
                          style: const TextStyle(
                            color: Colors.green,
                            fontWeight: FontWeight.w600,
                            fontSize: 12,
                          ),
                        ),
                    ],
                  ),
                ),

                const SizedBox(width: 8),
                const Icon(Icons.arrow_forward_ios_rounded, size: 14, color: Colors.grey),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStopIndicator(bool isPassed, bool isCurrent, bool isStudentStop) {
    if (isStudentStop) {
      return Container(
        width: 26,
        height: 26,
        decoration: const BoxDecoration(
          color: PRIMARY_BLUE,
          shape: BoxShape.circle,
        ),
        child: const Icon(Icons.star_rounded, color: Colors.white, size: 16),
      );
    }
    if (isCurrent) {
      return Container(
        width: 24,
        height: 24,
        padding: const EdgeInsets.all(2),
        decoration: const BoxDecoration(
          color: Colors.green,
          shape: BoxShape.circle,
        ),
        child: ClipOval(
          child: Image.asset(
            'assets/icon/icon.png',
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => const Icon(
              Icons.directions_bus_rounded,
              color: Colors.white,
              size: 14,
            ),
          ),
        ),
      );
    }
    return Container(
      width: 16,
      height: 16,
      decoration: BoxDecoration(
        color: isPassed ? SECONDARY_BLUE : Colors.white,
        shape: BoxShape.circle,
        border: Border.all(
          color: isPassed ? SECONDARY_BLUE : Colors.grey.shade400,
          width: 2,
        ),
      ),
      child: isPassed
          ? const Icon(Icons.check, color: Colors.white, size: 10)
          : null,
    );
  }

  Widget _buildTripDirectionBanner() {
    final isEvening = _tripDirection == 'evening';
    final label = isEvening
        ? (languageService.isTamil ? 'மாலை பயணம் (இறக்கம்)' : 'Evening Trip (Drop-off)')
        : (languageService.isTamil ? 'காலை பயணம் (ஏற்றம்)' : 'Morning Trip (Pickup)');

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
      margin: const EdgeInsets.only(top: 8, left: 16, right: 16, bottom: 4),
      decoration: BoxDecoration(
        color: isEvening ? const Color(0xFFEEF2FF) : const Color(0xFFFFFBEB),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isEvening ? const Color(0xFFC7D2FE) : const Color(0xFFFDE68A),
        ),
      ),
      child: Row(
        children: [
          Icon(
            isEvening ? Icons.nights_stay_rounded : Icons.wb_sunny_rounded,
            color: isEvening ? const Color(0xFF4338CA) : const Color(0xFFD97706),
            size: 18,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                color: isEvening ? const Color(0xFF3730A3) : const Color(0xFF92400E),
                fontWeight: FontWeight.bold,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomBar() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            Expanded(
              child: ElevatedButton.icon(
                onPressed: _openVoiceAssistant,
                icon: const Icon(Icons.mic, size: 20),
                label: Text(
                  languageService.isTamil ? 'குரல் உதவி' : 'Voice Help',
                  overflow: TextOverflow.ellipsis,
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: PRIMARY_BLUE,
                  foregroundColor: Colors.white,
                  minimumSize: const Size(0, 48),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: ElevatedButton.icon(
                onPressed: () => _viewOnMap(),
                icon: const Icon(Icons.map_outlined, size: 20),
                label: Text(
                  languageService.isTamil ? 'வரைபடத்தில் பார்க்க' : 'View on map',
                  overflow: TextOverflow.ellipsis,
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: SECONDARY_BLUE,
                  foregroundColor: Colors.white,
                  minimumSize: const Size(0, 48),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}