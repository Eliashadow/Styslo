import 'package:flutter/material.dart';

class SettingsScreen extends StatefulWidget {
  final String initialLanguage;
  final ValueChanged<String> onLanguageChanged;
  final double initialSpeechRate;
  final ValueChanged<double> onSpeechRateChanged;
  final String initialCommandMode;
  final ValueChanged<String> onCommandModeChanged;

  const SettingsScreen({
    super.key,

    required this.initialLanguage,
    required this.initialSpeechRate,
    required this.onLanguageChanged,
    required this.onSpeechRateChanged,
    required this.initialCommandMode,
    required this.onCommandModeChanged,

  });

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late String _selectedLanguage;
  late String _selectedCommandMode;
  late double _speechRate;

  final List<String> _allowedLanguages = ["uk-UA", "en-US", "en-UK"];

  @override
  void initState() {
    super.initState();
    _selectedLanguage = widget.initialLanguage;
    _selectedCommandMode = widget.initialCommandMode;
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
                border: Border.all(color: Colors.blueAccent.withValues(alpha: 0.5)),
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

            const SizedBox(height: 30), 
            
            Card(
              color: Colors.grey[900],
              margin: EdgeInsets.zero, 
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
                side: BorderSide(color: Colors.blueAccent.withValues(alpha: 0.5)),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                child: SwitchListTile(
                  title: const Text(
                    "Mode \"Ok, Styslo\"",
                    style: TextStyle(color: Colors.white, fontSize: 16),
                  ),
                  subtitle: Text(
                    _selectedCommandMode == 'ok, styslo' ? "Voice activation" : "Button control",
                    style: TextStyle(
                      color: _selectedCommandMode == 'ok, styslo' ? Colors.blueAccent : Colors.grey,
                      fontSize: 13,
                    ),
                  ),
                  secondary: Icon(
                    Icons.mic,
                    color: _selectedCommandMode == 'ok, styslo' ? Colors.blueAccent : Colors.grey,
                  ),
                  activeThumbColor: Colors.blueAccent,
                  activeTrackColor: Colors.blue.withValues(alpha: 0.3),
                  inactiveThumbColor: Colors.grey[400],
                  inactiveTrackColor: Colors.black26,
                  value: _selectedCommandMode == 'ok, styslo',
                  onChanged: (bool value) async {
                    final String nextMode = value ? 'ok, styslo' : 'button';
                    
                    setState(() {
                      _selectedCommandMode = nextMode;
                    });
                    
                    await Future.delayed(const Duration(milliseconds: 190));

                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      widget.onCommandModeChanged(nextMode);
                    });
                  },
                ),
              ),
            ), 
          ], 
        ), //
      ),
    );
  }
}