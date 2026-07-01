import 'package:flutter/material.dart';

class SettingsScreen extends StatefulWidget {
  final String initialLanguage;
  final ValueChanged<String> onLanguageChanged;
  final double initialSpeechRate;
  final ValueChanged<double> onSpeechRateChanged;

  const SettingsScreen({
    Key? key,
    required this.initialLanguage,
    required this.initialSpeechRate,
    required this.onLanguageChanged,
    required this.onSpeechRateChanged,

  }) : super(key: key);

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late String _selectedLanguage;
  late double _speechRate;
  final List<String> _allowedLanguages = ["uk-UA", "en-US", "en-UK"];

  @override
  void initState() {
    super.initState();
    _selectedLanguage = widget.initialLanguage;
    _speechRate = widget.initialSpeechRate;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black, 
      appBar: AppBar(
        title: const Text("Settings"),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            //language
            const Text(
              "Language (TTS)",
              style: TextStyle(color: Colors.grey, fontSize: 14, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.grey[900],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.blueAccent.withOpacity(0.5)),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _selectedLanguage,
                  dropdownColor: Colors.grey[900],
                  style: const TextStyle(color: Colors.white, fontSize: 16),
                  icon: const Icon(Icons.arrow_drop_down, color: Colors.blueAccent),
                  isExpanded: true,
                  items: _allowedLanguages.map((String lang) {
                    String displayName = lang;
                    if (lang == "uk-UA") displayName = "Українська (uk-UA)";
                    if (lang == "en-US") displayName = "English (en-US)";
                    if (lang == "en-UK") displayName = "English (en-UK)";
                    return DropdownMenuItem<String>(value: lang, child: Text(displayName));
                  }).toList(),
                  onChanged: (String? newValue) {
                    if (newValue != null) {
                      setState(() => _selectedLanguage = newValue);
                      widget.onLanguageChanged(newValue);
                    }
                  },
                ),
              ),
            ),
            
            const SizedBox(height: 30), 

            // --- spech rate ---
            Text(
              "Speech rate: ${_speechRate.toStringAsFixed(1)}",
              style: const TextStyle(color: Colors.grey, fontSize: 14, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            Slider(
              value: _speechRate,
              min: 0.1,
              max: 1.0,
              activeColor: Colors.blueAccent,
              inactiveColor: Colors.grey[800],
              onChanged: (value) {
                setState(() => _speechRate = value);
                widget.onSpeechRateChanged(value); 
              },
            ),
          ],
        ),
      ),
    );
  }
}