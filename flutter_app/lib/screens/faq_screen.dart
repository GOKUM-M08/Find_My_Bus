import 'package:flutter/material.dart';
import '../services/language_service.dart';

const Color PRIMARY_BLUE = Color(0xFF0052CC);
const Color SECONDARY_BLUE = Color(0xFF1E6BFF);
const Color LIGHT_BLUE = Color(0xFFE8F0FE);
const Color BACKGROUND_BLUE = Color(0xFFF7F9FC);

class FAQScreen extends StatefulWidget {
  const FAQScreen({super.key});

  @override
  State<FAQScreen> createState() => _FAQScreenState();
}

class _FAQScreenState extends State<FAQScreen> {
  final languageService = LanguageService();
  String _searchQuery = '';

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: languageService,
      builder: (context, _) {
        final isTa = languageService.isTamil;

        final faqs = isTa ? _tamilFAQs : _englishFAQs;
        final filtered = faqs.where((item) {
          final q = item['q']!.toLowerCase();
          final a = item['a']!.toLowerCase();
          final query = _searchQuery.toLowerCase();
          return _searchQuery.isEmpty || q.contains(query) || a.contains(query);
        }).toList();

        return Scaffold(
          backgroundColor: BACKGROUND_BLUE,
          appBar: AppBar(
            backgroundColor: PRIMARY_BLUE,
            foregroundColor: Colors.white,
            elevation: 4,
            title: Text(
              isTa ? 'கேள்விகள் & உதவி மையம' : 'FAQ & Help Center',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
            ),
          ),
          body: Column(
            children: [
              // Search Bar Header
              Container(
                color: PRIMARY_BLUE,
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: TextField(
                  onChanged: (val) => setState(() => _searchQuery = val),
                  decoration: InputDecoration(
                    hintText: isTa ? 'கேள்விகளைத் தேடுங்கள்...' : 'Search help articles & FAQs...',
                    prefixIcon: const Icon(Icons.search, color: PRIMARY_BLUE),
                    filled: true,
                    fillColor: Colors.white,
                    contentPadding: const EdgeInsets.symmetric(vertical: 12),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),

              Expanded(
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    if (filtered.isEmpty)
                      const Padding(
                        padding: EdgeInsets.all(32),
                        child: Center(
                          child: Text(
                            'No matching FAQ topics found.',
                            style: TextStyle(color: Colors.grey),
                          ),
                        ),
                      )
                    else
                      ...filtered.map((faq) => Container(
                            margin: const EdgeInsets.only(bottom: 10),
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
                            child: ExpansionTile(
                              leading: const CircleAvatar(
                                backgroundColor: LIGHT_BLUE,
                                child: Icon(Icons.quiz_rounded, color: PRIMARY_BLUE, size: 20),
                              ),
                              title: Text(
                                faq['q']!,
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                              ),
                              children: [
                                Padding(
                                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                                  child: Text(
                                    faq['a']!,
                                    style: const TextStyle(fontSize: 13, color: Colors.blueGrey, height: 1.4),
                                  ),
                                ),
                              ],
                            ),
                          )),

                    const SizedBox(height: 20),

                    // Still need help section
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: LIGHT_BLUE,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: PRIMARY_BLUE.withOpacity(0.3)),
                      ),
                      child: Column(
                        children: [
                          const Icon(Icons.support_agent_rounded, size: 40, color: PRIMARY_BLUE),
                          const SizedBox(height: 8),
                          Text(
                            isTa ? 'இன்னும் உதவி தேவையா?' : 'Still Need Direct Help?',
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: PRIMARY_BLUE),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            isTa ? 'எங்கள் 24/7 ஆதரவு குழுவை தொடர்பு கொள்ளவும்.' : 'Our dedicated support team is available 24/7 for parents.',
                            style: const TextStyle(fontSize: 12, color: Colors.blueGrey),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 12),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              ElevatedButton.icon(
                                style: ElevatedButton.styleFrom(backgroundColor: PRIMARY_BLUE, foregroundColor: Colors.white),
                                onPressed: () {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text('Calling Support: +91 6369669753')),
                                  );
                                },
                                icon: const Icon(Icons.phone, size: 16),
                                label: Text(isTa ? 'அழைப்பு' : 'Call Support'),
                              ),
                            ],
                          ),
                        ],
                      ),
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

  static const List<Map<String, String>> _englishFAQs = [
    {
      'q': 'How to track my child\'s bus live on the map?',
      'a': 'Simply enter the Bus Number or School Name in the search bar on the home screen. Tap the bus card to open real-time tracking.'
    },
    {
      'q': 'How frequently does the bus location update?',
      'a': 'Locations update automatically every 10 seconds via AIS 140 hardware GPS units mounted on the school bus.'
    },
    {
      'q': 'What happens if a bus is delayed or stuck in traffic?',
      'a': 'The app computes real-time traffic delays and updates the estimated time of arrival (ETA) for each upcoming stop.'
    },
    {
      'q': 'Is student location data kept private and secure?',
      'a': 'Yes. All data transmissions are encrypted using SSL/TLS, and location sessions automatically expire to protect student privacy.'
    },
    {
      'q': 'How do drivers start broadcast mode?',
      'a': 'Drivers click "Driver Login" from the menu or home screen, authenticate, and toggle the Driver Broadcast Mode switch.'
    },
  ];

  static const List<Map<String, String>> _tamilFAQs = [
    {
      'q': 'எனது குழந்தையின் பேருந்தை நேரலையில் எவ்வாறு கண்காணிப்பது?',
      'a': 'முகப்புத் திரையில் உள்ள தேடல் பெட்டியில் பேருந்து எண் அல்லது பள்ளியின் பெயரை தட்டச்சு செய்க. நேரலை இருப்பிடத்தைப் பார்க்க பேருந்து அட்டையைத் தட்டவும்.'
    },
    {
      'q': 'பேருந்து இருப்பிடம் எவ்வளவு அடிக்கடி புதுப்பிக்கப்படும்?',
      'a': 'பள்ளிப் பேருந்தில் பொருத்தப்பட்டுள்ள AIS 140 ஜிபிஎஸ் சாதனம் மூலம் ஒவ்வொரு 10 வினாடியிலும் இருப்பிடம் தானாகப் புதுப்பிக்கப்படும்.'
    },
    {
      'q': 'பேருந்து தாமதமானால் என்ன நடக்கும்?',
      'a': 'செயலி நேரலை போக்குவரத்து தாமதங்களை கணக்கிட்டு, ஒவ்வொரு நிறுத்தத்திற்கும் எதிர்பார்க்கப்படும் நேரத்தைப் (ETA) புதுப்பிக்கும்.'
    },
    {
      'q': 'மாணவர்களின் இருப்பிடத் தரவு பாதுகாப்பானதா?',
      'a': 'ஆம். அனைத்துத் தரவுகளும் SSL/TLS மூலம் பாதுகாப்பாக குறியாக்கம் செய்யப்படுகின்றன.'
    },
  ];
}
