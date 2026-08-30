import 'package:flutter/material.dart';
import '../services/language_service.dart';

const Color PRIMARY_BLUE = Color(0xFF0052CC);
const Color SECONDARY_BLUE = Color(0xFF1E6BFF);
const Color LIGHT_BLUE = Color(0xFFE8F0FE);
const Color BACKGROUND_BLUE = Color(0xFFF7F9FC);

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final languageService = LanguageService();

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
              isTa ? 'என் சுயவிவரம்' : 'My Profile',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
            ),
          ),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // User Avatar Card
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [PRIMARY_BLUE, SECONDARY_BLUE],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: PRIMARY_BLUE.withOpacity(0.25),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(4),
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                      ),
                      child: const CircleAvatar(
                        radius: 32,
                        backgroundColor: LIGHT_BLUE,
                        child: Icon(Icons.person_rounded, size: 40, color: PRIMARY_BLUE),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Parent / Student Guest',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            isTa ? 'நேரலை பேருந்து கண்காணிப்பு கணக்கு' : 'Live Bus Tracking Access Enabled',
                            style: const TextStyle(color: Colors.white70, fontSize: 12),
                          ),
                          const SizedBox(height: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.verified_user_rounded, size: 14, color: Colors.white),
                                const SizedBox(width: 4),
                                Text(
                                  isTa ? 'செயலிலுள்ளது' : 'Active Account',
                                  style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // Saved Favorites Section
              _buildSectionTitle(isTa ? 'பிடித்த பேருந்துகள் & வழித்தடங்கள்' : 'Saved Favorites & Tracking History'),
              const SizedBox(height: 10),
              _buildCardTile(
                icon: Icons.directions_bus_rounded,
                title: isTa ? 'பேருந்து #101 — சென்னை பள்ளி' : 'Bus #101 — St. John School',
                subtitle: isTa ? 'கடைசியாக பார்க்கப்பட்டது: 10 நிமிடங்களுக்கு முன்' : 'Last tracked 10 mins ago',
                trailing: const Icon(Icons.star_rounded, color: Colors.amber),
              ),
              _buildCardTile(
                icon: Icons.directions_bus_rounded,
                title: isTa ? 'பேருந்து #204 — கிரீன் அலி வழித்தடம்' : 'Bus #204 — Green Alley Route',
                subtitle: isTa ? 'கடைசியாக பார்க்கப்பட்டது: நேற்று' : 'Last tracked yesterday',
                trailing: const Icon(Icons.star_rounded, color: Colors.amber),
              ),

              const SizedBox(height: 20),

              // Account & Preferences
              _buildSectionTitle(isTa ? 'கணக்கு அமைப்புகள்' : 'Account Details & Preferences'),
              const SizedBox(height: 10),
              _buildInfoRow(
                icon: Icons.language_rounded,
                label: isTa ? 'தற்போதைய மொழி' : 'Selected Language',
                value: isTa ? 'தமிழ் (Tamil)' : 'English',
              ),
              _buildInfoRow(
                icon: Icons.security_rounded,
                label: isTa ? 'பாதுகாப்பு நிலை' : 'Security Mode',
                value: 'TLS / Encrypted GPS',
              ),
              _buildInfoRow(
                icon: Icons.phone_android_rounded,
                label: isTa ? 'சாதன வகை' : 'App Client',
                value: 'Find My Bus Mobile v1.2',
              ),

              const SizedBox(height: 24),

              // Emergency Contact Box
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: PRIMARY_BLUE.withOpacity(0.2)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.contact_support_rounded, color: PRIMARY_BLUE),
                        const SizedBox(width: 8),
                        Text(
                          isTa ? 'அவசர உதவி மையம்' : 'Emergency School Transport Helpdesk',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      isTa ? 'உங்கள் குழந்தையின் பேருந்து தாமதமானால் உதவி மையத்தை தொடர்பு கொள்ளவும்.' : 'Direct line to school transport helpline for delays or urgent inquiries.',
                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                    const Divider(height: 20),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('+91 6369669753', style: TextStyle(fontWeight: FontWeight.bold, color: PRIMARY_BLUE)),
                        ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(backgroundColor: PRIMARY_BLUE, foregroundColor: Colors.white),
                          onPressed: () {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Calling Transport Helpdesk...')),
                            );
                          },
                          icon: const Icon(Icons.call, size: 16),
                          label: Text(isTa ? 'அழைக்க' : 'Call Helpdesk'),
                        ),
                      ],
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
        fontSize: 14,
        fontWeight: FontWeight.bold,
        color: PRIMARY_BLUE,
        letterSpacing: 0.3,
      ),
    );
  }

  Widget _buildCardTile({
    required IconData icon,
    required String title,
    required String subtitle,
    Widget? trailing,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: LIGHT_BLUE,
          child: Icon(icon, color: PRIMARY_BLUE, size: 20),
        ),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
        subtitle: Text(subtitle, style: const TextStyle(fontSize: 11, color: Colors.grey)),
        trailing: trailing,
      ),
    );
  }

  Widget _buildInfoRow({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(icon, size: 20, color: PRIMARY_BLUE),
          const SizedBox(width: 12),
          Text(label, style: const TextStyle(fontSize: 13, color: Colors.blueGrey)),
          const Spacer(),
          Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}
