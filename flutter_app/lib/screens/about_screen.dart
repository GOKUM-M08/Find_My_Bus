import 'package:flutter/material.dart';
import '../services/language_service.dart';

const Color PRIMARY_BLUE = Color(0xFF0052CC);
const Color SECONDARY_BLUE = Color(0xFF1E6BFF);
const Color LIGHT_BLUE = Color(0xFFE8F0FE);
const Color BACKGROUND_BLUE = Color(0xFFF7F9FC);

class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final languageService = LanguageService();

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
              isTa ? 'பயன்பாட்டைப் பற்றி' : 'About Find My Bus',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
            ),
          ),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // Logo & App Identity Header
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.04),
                      blurRadius: 10,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: const BoxDecoration(
                        color: LIGHT_BLUE,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.directions_bus_rounded, size: 56, color: PRIMARY_BLUE),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      languageService.getText('app_title'),
                      style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: PRIMARY_BLUE),
                    ),
                    const SizedBox(height: 4),
                    const Text('v1.2.0 (Build 2026.08)', style: TextStyle(fontSize: 12, color: Colors.grey)),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.green.shade50,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.green.shade300),
                      ),
                      child: Text(
                        isTa ? 'அதிகாரப்பூர்வ பதிப்பு' : 'Official School Transport Platform',
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.green.shade800),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // Technology Architecture Stack
              Text(
                isTa ? 'தொழில்நுட்ப கட்டமைப்பு' : 'Platform Engineering Stack',
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: PRIMARY_BLUE),
              ),
              const SizedBox(height: 10),
              _buildFeatureTile(
                icon: Icons.radar_rounded,
                title: 'AIS 140 Hardware GPS Parser',
                subtitle: 'TCP Stream Server (Port 9000) listening for telemetry packets.',
              ),
              _buildFeatureTile(
                icon: Icons.auto_awesome_rounded,
                title: 'SciPy Hungarian Route Optimizer',
                subtitle: 'AI linear sum assignment for fuel, time, capacity & maintenance.',
              ),
              _buildFeatureTile(
                icon: Icons.cloud_done_rounded,
                title: 'Supabase Realtime Database',
                subtitle: 'Sub-second WebSocket broadcast to parent tracking screens.',
              ),
              _buildFeatureTile(
                icon: Icons.translate_rounded,
                title: 'English & Tamil Multi-Language System',
                subtitle: 'Full bilingual interface support for English and தமிழ்.',
              ),

              const SizedBox(height: 20),

              // Developer & Support Info
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isTa ? 'உரிமம் & ஆதரவு' : 'License & Support Info',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Designed & Built for School Transportation & Fleet Safety.\n'
                      'Copyright © 2026 Find My Bus Inc. All rights reserved.',
                      style: TextStyle(fontSize: 12, color: Colors.grey, height: 1.4),
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

  Widget _buildFeatureTile({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: LIGHT_BLUE,
          child: Icon(icon, color: PRIMARY_BLUE, size: 20),
        ),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
        subtitle: Text(subtitle, style: const TextStyle(fontSize: 11, color: Colors.blueGrey)),
      ),
    );
  }
}
