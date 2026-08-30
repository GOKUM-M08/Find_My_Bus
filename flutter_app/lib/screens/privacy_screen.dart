import 'package:flutter/material.dart';
import '../services/language_service.dart';

const Color PRIMARY_BLUE = Color(0xFF0052CC);
const Color SECONDARY_BLUE = Color(0xFF1E6BFF);
const Color LIGHT_BLUE = Color(0xFFE8F0FE);
const Color BACKGROUND_BLUE = Color(0xFFF7F9FC);

class PrivacyScreen extends StatelessWidget {
  const PrivacyScreen({super.key});

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
              isTa ? 'தனியுரிமைக் கொள்கை' : 'Privacy & Data Protection',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
            ),
          ),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.security_rounded, color: PRIMARY_BLUE, size: 28),
                        const SizedBox(width: 10),
                        Text(
                          isTa ? 'மாணவர் மற்றும் இருப்பிடப் பாதுகாப்பு' : 'Student Safety & Data Privacy',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      isTa
                          ? 'Find My Bus பயனர்களின் தனிப்பட்ட விவரங்கள் மற்றும் நேரலை ஜிபிஎஸ் தரவுகளை பாதுகாப்பாக பராமரிக்கிறது.'
                          : 'Find My Bus is committed to protecting student safety and ensuring location tracking data is securely managed.',
                      style: const TextStyle(fontSize: 13, color: Colors.blueGrey, height: 1.4),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              _buildPolicySection(
                title: isTa ? '1. இருப்பிடக் கண்காணிப்பு தரவு' : '1. Location & GPS Data Handling',
                body: isTa
                    ? 'பேருந்துகளின் நேரலை இருப்பிடத் தரவு 60 வினாடிகளுக்குப் பிறகு தானாகவே காலாவதியாகும். பெற்றோரின் இருப்பிடம் அல்லது தனிப்பட்ட விவரங்கள் சேகரிக்கப்படுவதில்லை.'
                    : 'School bus telemetry is streamed over encrypted TLS sockets. Location sessions expire after 60 seconds of inactivity. Parent device locations are never tracked or stored.',
              ),
              _buildPolicySection(
                title: isTa ? '2. மாணவர் விவரங்கள் பாதுகாப்பு' : '2. Student Seating & Route Scoping',
                body: isTa
                    ? 'மாணவர் தகவல்கள் மற்றும் பேருந்து ஒதுக்கீடு விவரங்கள் அங்கீகரிக்கப்பட்ட பள்ளி நிர்வாகிகளால் மட்டுமே அணுக முடியும்.'
                    : 'Student stop assignments and seat fit records are scoped strictly to authenticated school domain administrators.',
              ),
              _buildPolicySection(
                title: isTa ? '3. தரவு பாதுகாப்பு மற்றும் குறியாக்கம்' : '3. Security Safeguards & Encryption',
                body: isTa
                    ? 'அனைத்து தரவுகளும் Supabase மற்றும் FastAPI சேவையகங்களில் AES-256 குறியாக்கத்துடன் பாதுகாக்கப்படுகின்றன.'
                    : 'All backend communications use HTTPS/WSS protocols with AES-256 encrypted storage on Supabase infrastructure.',
              ),

              const SizedBox(height: 20),

              Center(
                child: Text(
                  isTa ? 'கடைசியாக புதுப்பிக்கப்பட்டது: ஆகஸ்ட் 2026' : 'Last Updated: August 2026',
                  style: const TextStyle(fontSize: 11, color: Colors.grey),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildPolicySection({required String title, required String body}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: PRIMARY_BLUE)),
          const SizedBox(height: 6),
          Text(body, style: const TextStyle(fontSize: 12, color: Colors.black87, height: 1.4)),
        ],
      ),
    );
  }
}
