import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'tracking_screen.dart';
import '../services/notification_service.dart';
import '../services/language_service.dart';
import '../widgets/voice_assistant_sheet.dart';

class StopsScreen extends StatefulWidget {
  final String busId;
  final String busNumber;
  final String schoolName;

  const StopsScreen({
    super.key,
    required this.busId,
    required this.busNumber,
    required this.schoolName,
  });

  @override
  State<StopsScreen> createState() => _StopsScreenState();
}

class _StopsScreenState extends State<StopsScreen> {
  final supabase = Supabase.instance.client;
  final languageService = LanguageService();
  final notificationService = NotificationService();

  List<Map<String, dynamic>> _stops = [];
  bool _loading = true;
  int _currentStopIndex = -1; // -1 = unknown / not yet moving
  bool _busIsLive = false;
  String? _selectedNotifStopId;
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    languageService.addListener(_onLanguageChanged);
    _loadSelectedNotificationStop();
    _loadStops();
    _refreshTimer = Timer.periodic(
      const Duration(seconds: 15),
      (_) => _refreshBusPosition(),
    );
  }

  @override
  void dispose() {
    languageService.removeListener(_onLanguageChanged);
    _refreshTimer?.cancel();
    super.dispose();
  }

  void _onLanguageChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _loadSelectedNotificationStop() async {
    final stopId = await notificationService.getSelectedStopId(widget.busId);
    if (mounted) {
      setState(() => _selectedNotifStopId = stopId);
    }
  }

  Future<void> _selectNotificationStop(Map<String, dynamic> stop) async {
    final stopId = str(stop['id']);
    final stopName = stop['stop_name'] ?? 'Stop';

    await notificationService.switchSelectedStop(widget.busId, stopId);

    if (!mounted) return;
    setState(() => _selectedNotifStopId = stopId);

    final msgTemplate = languageService.getText('subscribed_to_stop');
    final msg = msgTemplate.replaceAll('{stop}', stopName);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.notifications_active, color: Colors.white),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                msg,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        backgroundColor: const Color(0xFF0052CC),
        duration: const Duration(seconds: 3),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  String str(dynamic val) => val?.toString() ?? '';

  Future<void> _loadStops() async {
    final routeResult = await supabase
        .from('routes')
        .select('id')
        .eq('bus_id', widget.busId)
        .maybeSingle();

    if (routeResult == null) {
      setState(() => _loading = false);
      return;
    }

    final stopsResult = await supabase
        .from('stops')
        .select('id, stop_name, latitude, longitude, stop_order, expected_time')
        .eq('route_id', routeResult['id'])
        .order('stop_order');

    setState(() {
      _stops = List<Map<String, dynamic>>.from(stopsResult).reversed.toList();
      _loading = false;
    });

    await _refreshBusPosition();
  }

  Future<void> _refreshBusPosition() async {
    if (_stops.isEmpty) return;
    final locResult = await supabase
        .from('live_location')
        .select('latitude, longitude, timestamp')
        .eq('bus_id', widget.busId)
        .maybeSingle();

    if (locResult == null) {
      if (mounted) setState(() => _busIsLive = false);
      return;
    }

    final rawTimestamp = locResult['timestamp'];
    if (rawTimestamp == null) {
      if (mounted) setState(() => _busIsLive = false);
      return;
    }
    final lastUpdate = DateTime.parse(rawTimestamp).toUtc();
    final secondsAgo = DateTime.now().toUtc().difference(lastUpdate).inSeconds;
    final isRecent = secondsAgo < 60;

    if (!isRecent) {
      if (mounted) setState(() => _busIsLive = false);
      return;
    }

    final busLat = (locResult['latitude'] as num).toDouble();
    final busLon = (locResult['longitude'] as num).toDouble();

    double minDistance = double.infinity;
    int nearestIndex = 0;
    for (int i = 0; i < _stops.length; i++) {
      final d = _haversine(
        busLat, busLon,
        (_stops[i]['latitude'] as num).toDouble(),
        (_stops[i]['longitude'] as num).toDouble(),
      );
      if (d < minDistance) {
        minDistance = d;
        nearestIndex = i;
      }
    }

    if (!mounted) return;
    setState(() {
      _currentStopIndex = nearestIndex;
      _busIsLive = true;
    });
  }

  double _haversine(double lat1, double lon1, double lat2, double lon2) {
    const r = 6371.0;
    final dLat = _deg2rad(lat2 - lat1);
    final dLon = _deg2rad(lon2 - lon1);
    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(_deg2rad(lat1)) *
            cos(_deg2rad(lat2)) *
            sin(dLon / 2) *
            sin(dLon / 2);
    final c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return r * c;
  }

  double _deg2rad(double deg) => deg * (pi / 180);

  void _viewOnMap({String? stopId}) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => TrackingScreen(
          busId: widget.busId,
          busNumber: widget.busNumber,
          stopId: stopId ?? _selectedNotifStopId,
        ),
      ),
    );
  }

  void _openVoiceAssistant() {
    VoiceAssistantSheet.show(
      context,
      busId: widget.busId,
      busNumber: widget.busNumber,
      stopId: _selectedNotifStopId,
    );
  }

  @override
  Widget build(BuildContext context) {
    final selectedStopObj = _stops.firstWhere(
      (s) => str(s['id']) == _selectedNotifStopId,
      orElse: () => {},
    );
    final selectedStopName = selectedStopObj['stop_name'];

    return Scaffold(
      backgroundColor: const Color(0xFFF3F5F9),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E6BFF),
        foregroundColor: Colors.white,
        elevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${languageService.getText('bus')} ${widget.busNumber}',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
            ),
            if (widget.schoolName.isNotEmpty)
              Text(
                widget.schoolName,
                style: const TextStyle(fontSize: 12, color: Colors.white70),
              ),
          ],
        ),
        actions: [
          // Voice Assistant Mic Button
          IconButton(
            tooltip: languageService.getText('voice_assistant_title'),
            icon: const Icon(Icons.mic_rounded),
            onPressed: _openVoiceAssistant,
          ),

          // Tamil/English Toggle
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
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _stops.isEmpty
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(32),
                    child: Text(
                      'No stops have been set up for this bus yet.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey),
                    ),
                  ),
                )
              : Column(
                  children: [
                    if (_busIsLive)
                      Container(
                        width: double.infinity,
                        color: Colors.green.shade50,
                        padding: const EdgeInsets.symmetric(
                            vertical: 8, horizontal: 16),
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
                                  fontSize: 13,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),

                    // Notification Stop Header Banner
                    Container(
                      width: double.infinity,
                      margin: const EdgeInsets.all(12),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFF1E6BFF).withOpacity(0.3)),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.04),
                            blurRadius: 6,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: const Color(0xFFE8F0FE),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(
                              Icons.notifications_active,
                              color: Color(0xFF0052CC),
                              size: 22,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  languageService.getText('select_stop_notify'),
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14,
                                    color: Color(0xFF0F172A),
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  selectedStopName != null
                                      ? languageService
                                          .getText('notification_stop_set')
                                          .replaceAll('{stop}', selectedStopName)
                                      : languageService.getText('no_stop_selected'),
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: selectedStopName != null
                                        ? const Color(0xFF0052CC)
                                        : Colors.grey,
                                    fontWeight: selectedStopName != null
                                        ? FontWeight.bold
                                        : FontWeight.normal,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                  maxLines: 2,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),

                    Expanded(
                      child: ListView.builder(
                        padding: const EdgeInsets.symmetric(
                            vertical: 8, horizontal: 16),
                        itemCount: _stops.length + 1,
                        itemBuilder: (context, index) {
                          if (index == 0) {
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 12),
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
                    _buildBottomButton(),
                  ],
                ),
    );
  }

  Widget _buildStopRow(int index) {
    final stop = _stops[index];
    final stopId = str(stop['id']);
    final isPassed = _currentStopIndex >= 0 && index < _currentStopIndex;
    final isCurrent = _currentStopIndex == index;
    final isSelectedForNotif = _selectedNotifStopId == stopId;

    return IntrinsicHeight(
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: isSelectedForNotif
              ? const Color(0xFFE8F0FE)
              : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelectedForNotif
                ? const Color(0xFF0052CC)
                : Colors.grey.shade300,
            width: isSelectedForNotif ? 2 : 1,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Timeline dot
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _StopDot(
                  isPassed: isPassed,
                  isCurrent: isCurrent,
                  isSelectedNotif: isSelectedForNotif,
                ),
              ],
            ),
            const SizedBox(width: 12),

            // Stop Info
            Expanded(
              child: InkWell(
                onTap: () => _viewOnMap(stopId: stop['id']),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            stop['stop_name'] ?? '',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: (isCurrent || isSelectedForNotif)
                                  ? FontWeight.bold
                                  : FontWeight.w600,
                              color: isPassed ? Colors.grey : const Color(0xFF0F172A),
                            ),
                          ),
                        ),
                        if (stop['expected_time'] != null)
                          Text(
                            stop['expected_time'],
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: isPassed ? Colors.grey : Colors.black54,
                            ),
                          ),
                      ],
                    ),
                    if (isSelectedForNotif)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.notifications_active_rounded,
                              size: 14,
                              color: Color(0xFF0052CC),
                            ),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                languageService.getText('stop_notif_active'),
                                style: const TextStyle(
                                  color: Color(0xFF0052CC),
                                  fontWeight: FontWeight.bold,
                                  fontSize: 11,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      )
                    else if (isCurrent)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          languageService.isTamil ? 'பேருந்து இங்கு உள்ளது' : 'Bus is near here',
                          style: const TextStyle(
                            color: Colors.green,
                            fontWeight: FontWeight.w600,
                            fontSize: 12,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),

            const SizedBox(width: 8),

            // Select Stop Notification Button (Bell Icon)
            IconButton(
              tooltip: languageService.getText('select_stop_notify'),
              onPressed: () => _selectNotificationStop(stop),
              icon: Icon(
                isSelectedForNotif
                    ? Icons.notifications_active
                    : Icons.notifications_none_outlined,
                color: isSelectedForNotif
                    ? const Color(0xFF0052CC)
                    : Colors.grey.shade600,
                size: 24,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomButton() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
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
                  backgroundColor: const Color(0xFF0052CC),
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
                  backgroundColor: const Color(0xFF1E6BFF),
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

class _StopDot extends StatelessWidget {
  final bool isPassed;
  final bool isCurrent;
  final bool isSelectedNotif;

  const _StopDot({
    required this.isPassed,
    required this.isCurrent,
    required this.isSelectedNotif,
  });

  @override
  Widget build(BuildContext context) {
    if (isSelectedNotif) {
      return Container(
        width: 22,
        height: 22,
        decoration: const BoxDecoration(
          color: Color(0xFF0052CC),
          shape: BoxShape.circle,
        ),
        child: const Icon(Icons.notifications, color: Colors.white, size: 13),
      );
    }
    if (isCurrent) {
      return Container(
        width: 20,
        height: 20,
        decoration: const BoxDecoration(
          color: Colors.green,
          shape: BoxShape.circle,
        ),
        child: const Icon(Icons.directions_bus, color: Colors.white, size: 12),
      );
    }
    return Container(
      width: 14,
      height: 14,
      margin: const EdgeInsets.symmetric(vertical: 3),
      decoration: BoxDecoration(
        color: isPassed ? const Color(0xFF1E6BFF) : Colors.white,
        shape: BoxShape.circle,
        border: Border.all(
          color: isPassed ? const Color(0xFF1E6BFF) : Colors.grey.shade400,
          width: 2,
        ),
      ),
      child: isPassed
          ? const Icon(Icons.check, color: Colors.white, size: 10)
          : null,
    );
  }
}