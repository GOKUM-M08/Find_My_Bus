import 'package:flutter/material.dart';
import '../services/language_service.dart';

const Color PRIMARY_BLUE = Color(0xFF0052CC);
const Color SECONDARY_BLUE = Color(0xFF1E6BFF);
const Color LIGHT_BLUE = Color(0xFFE8F0FE);
const Color BACKGROUND_BLUE = Color(0xFFF7F9FC);

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final languageService = LanguageService();

  bool _overspeedAlerts = true;
  bool _etaNotifications = true;
  bool _soundEnabled = true;
  double _refreshIntervalSec = 10.0;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: languageService,
      builder: (context, _) {
        final isTa = languageService.isTamil;

        return Scaffold(
          backgroundColor: BACKGROUND_BLUE,
          appBar: AppBar(
            backgroundColor: PRIMARY_BLUE,
            foregroundColor: Colors.white,
            elevation: 4,
            title: Text(
              isTa ? 'தீம் & அமைப்புகள்' : 'Theme & Settings',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
            ),
          ),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // Language Quick Switcher Section
              _buildSectionTitle(isTa ? 'மொழி அமைப்புகள்' : 'Language Preferences'),
              const SizedBox(height: 8),
              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Column(
                  children: [
                    RadioListTile<String>(
                      value: 'en',
                      groupValue: languageService.currentLanguage,
                      title: const Text('English (Default)', style: TextStyle(fontWeight: FontWeight.bold)),
                      activeColor: PRIMARY_BLUE,
                      onChanged: (val) {
                        if (val != null) languageService.setLanguage(val);
                      },
                    ),
                    const Divider(height: 1),
                    RadioListTile<String>(
                      value: 'ta',
                      groupValue: languageService.currentLanguage,
                      title: const Text('தமிழ் (Tamil)', style: TextStyle(fontWeight: FontWeight.bold)),
                      activeColor: PRIMARY_BLUE,
                      onChanged: (val) {
                        if (val != null) languageService.setLanguage(val);
                      },
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // GPS Refresh & Performance Settings
              _buildSectionTitle(isTa ? 'ஜிபிஎஸ் புதுப்பிப்பு அமைப்புகள்' : 'Live Tracking Performance'),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          isTa ? 'நேரலை புதுப்பிப்பு இடைவெளி' : 'Live GPS Refresh Interval',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: LIGHT_BLUE,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            '${_refreshIntervalSec.toInt()} sec',
                            style: const TextStyle(fontWeight: FontWeight.bold, color: PRIMARY_BLUE, fontSize: 12),
                          ),
                        ),
                      ],
                    ),
                    Slider(
                      value: _refreshIntervalSec,
                      min: 5,
                      max: 30,
                      divisions: 5,
                      activeColor: PRIMARY_BLUE,
                      onChanged: (val) => setState(() => _refreshIntervalSec = val),
                    ),
                    Text(
                      isTa ? 'குறைந்த இடைவெளி அதிவேக நேரலை கண்காணிப்பை வழங்கும்.' : 'Faster refresh interval provides sub-second GPS tracking on the map.',
                      style: const TextStyle(fontSize: 11, color: Colors.grey),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // Notifications & Alerts
              _buildSectionTitle(isTa ? 'அறிவிப்பு அமைப்புகள்' : 'Notification Preferences'),
              const SizedBox(height: 8),
              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Column(
                  children: [
                    SwitchListTile(
                      value: _overspeedAlerts,
                      activeColor: PRIMARY_BLUE,
                      title: Text(isTa ? 'அதிவேக எச்சரிக்கைகள்' : 'Overspeed Warnings'),
                      subtitle: Text(isTa ? 'பேருந்து 60 கி.மீ/மணிக்கு மேல் சென்றால் எச்சரிக்கவும்' : 'Alert when bus exceeds 60 km/h threshold'),
                      onChanged: (val) => setState(() => _overspeedAlerts = val),
                    ),
                    const Divider(height: 1),
                    SwitchListTile(
                      value: _etaNotifications,
                      activeColor: PRIMARY_BLUE,
                      title: Text(isTa ? 'வருகை அறிவிப்புகள்' : 'Bus Stop Arrival Warnings'),
                      subtitle: Text(isTa ? 'பேருந்து வருகைக்கு 5 நிமிடங்களுக்கு முன் அறிவிக்கும்' : 'Notify 5 minutes before bus arrives at stop'),
                      onChanged: (val) => setState(() => _etaNotifications = val),
                    ),
                    const Divider(height: 1),
                    SwitchListTile(
                      value: _soundEnabled,
                      activeColor: PRIMARY_BLUE,
                      title: Text(isTa ? 'ஒலி விழிப்பூட்டல்கள்' : 'Alert Chime Sound'),
                      onChanged: (val) => setState(() => _soundEnabled = val),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: const TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.bold,
        color: PRIMARY_BLUE,
      ),
    );
  }
}
