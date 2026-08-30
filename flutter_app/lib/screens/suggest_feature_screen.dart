import 'package:flutter/material.dart';
import '../services/language_service.dart';

const Color PRIMARY_BLUE = Color(0xFF0052CC);
const Color SECONDARY_BLUE = Color(0xFF1E6BFF);
const Color LIGHT_BLUE = Color(0xFFE8F0FE);
const Color BACKGROUND_BLUE = Color(0xFFF7F9FC);

class SuggestFeatureScreen extends StatefulWidget {
  const SuggestFeatureScreen({super.key});

  @override
  State<SuggestFeatureScreen> createState() => _SuggestFeatureScreenState();
}

class _SuggestFeatureScreenState extends State<SuggestFeatureScreen> {
  final languageService = LanguageService();
  final _titleController = TextEditingController();
  final _descController = TextEditingController();

  String _selectedCategory = 'Live Tracking';
  String _selectedPriority = 'Medium';

  final List<Map<String, String>> _submittedSuggestions = [
    {
      'title': 'Add Audio Voice Alerts for Approaching Stop',
      'category': 'Notifications',
      'status': 'In Review',
      'date': 'Yesterday',
    },
    {
      'title': 'Dark Mode Option for Night Driving',
      'category': 'UI & Theme',
      'status': 'Planned',
      'date': '3 days ago',
    },
  ];

  @override
  void dispose() {
    _titleController.dispose();
    _descController.dispose();
    super.dispose();
  }

  void _submitFeature() {
    if (_titleController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a title for your suggestion')),
      );
      return;
    }

    setState(() {
      _submittedSuggestions.insert(0, {
        'title': _titleController.text.trim(),
        'category': _selectedCategory,
        'status': 'Under Review',
        'date': 'Just now',
      });
      _titleController.clear();
      _descController.clear();
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          languageService.isTamil
              ? 'மிக்க நன்றி! உங்கள் அம்சப் பரிந்துரை சமர்ப்பிக்கப்பட்டது.'
              : 'Thank you! Your feature suggestion has been submitted.',
        ),
        backgroundColor: Colors.green.shade800,
      ),
    );
  }

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
              isTa ? 'அம்சத்தைப் பரிந்துரைக்க' : 'Suggest a Feature',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
            ),
          ),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // Form Header Card
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.03),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.lightbulb_rounded, color: Colors.orange, size: 24),
                        const SizedBox(width: 10),
                        Text(
                          isTa ? 'புதிய அம்சத்தைப் பரிந்துரைக்கவும்' : 'Submit Feature Feedback',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      isTa
                          ? 'Find My Bus செயலியை மேம்படுத்த உங்கள் யோசனைகளைப் பகிரவும்.'
                          : 'Help us make Find My Bus better for parents, drivers & schools.',
                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                    const SizedBox(height: 16),

                    // Feature Title Input
                    TextField(
                      controller: _titleController,
                      decoration: InputDecoration(
                        labelText: isTa ? 'தலைப்பு (Title)' : 'Feature Title',
                        hintText: isTa ? 'எடுத்துக்காட்டு: குரல் எச்சரிக்கை' : 'e.g. Speedometer display widget',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Category Dropdown
                    Row(
                      children: [
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            value: _selectedCategory,
                            decoration: InputDecoration(
                              labelText: isTa ? 'வகை (Category)' : 'Category',
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                            items: const [
                              DropdownMenuItem(value: 'Live Tracking', child: Text('Live Tracking')),
                              DropdownMenuItem(value: 'Notifications', child: Text('Notifications')),
                              DropdownMenuItem(value: 'Route Optimizer', child: Text('Route Optimizer')),
                              DropdownMenuItem(value: 'UI & Theme', child: Text('UI & Theme')),
                            ],
                            onChanged: (val) {
                              if (val != null) setState(() => _selectedCategory = val);
                            },
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            value: _selectedPriority,
                            decoration: InputDecoration(
                              labelText: isTa ? 'முன்னுரிமை' : 'Priority',
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                            items: const [
                              DropdownMenuItem(value: 'Low', child: Text('Low')),
                              DropdownMenuItem(value: 'Medium', child: Text('Medium')),
                              DropdownMenuItem(value: 'High', child: Text('High')),
                            ],
                            onChanged: (val) {
                              if (val != null) setState(() => _selectedPriority = val);
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),

                    // Description Input
                    TextField(
                      controller: _descController,
                      maxLines: 4,
                      decoration: InputDecoration(
                        labelText: isTa ? 'விளக்கம் (Description)' : 'Detailed Description',
                        hintText: isTa ? 'உங்கள் யோசனையை விரிவாக விளக்குங்கள்...' : 'Explain why this feature would be helpful...',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                    const SizedBox(height: 16),

                    SizedBox(
                      width: double.infinity,
                      height: 46,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: PRIMARY_BLUE,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        onPressed: _submitFeature,
                        icon: const Icon(Icons.send_rounded, size: 18),
                        label: Text(
                          isTa ? 'பரிந்துரையைச் சமர்ப்பி' : 'Submit Suggestion',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // Recent Feedback Submissions History
              Text(
                isTa ? 'சமீபத்திய பரிந்துரைகள்' : 'Your Submitted Suggestions',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: PRIMARY_BLUE),
              ),
              const SizedBox(height: 10),

              ..._submittedSuggestions.map((item) => Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: ListTile(
                      leading: const CircleAvatar(
                        backgroundColor: LIGHT_BLUE,
                        child: Icon(Icons.lightbulb_outline, color: PRIMARY_BLUE, size: 20),
                      ),
                      title: Text(item['title']!, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                      subtitle: Text('${item['category']} • ${item['date']}'),
                      trailing: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: PRIMARY_BLUE.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          item['status']!,
                          style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: PRIMARY_BLUE),
                        ),
                      ),
                    ),
                  )),
            ],
          ),
        );
      },
    );
  }
}
