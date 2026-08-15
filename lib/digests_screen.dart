// This screen to generate digests and manage digest settings also there will be detailed history 

// ====  Essential imports ==== 
import 'dart:async';
import 'package:flutter/material.dart';


// Variables
class DigestsScreen extends StatefulWidget {
  // ====  Language ==== 
  final String initialLanguage;
  final ValueChanged<String> onLanguageChanged;
  // ====  SpeechRate ==== 
  final double initialSpeechRate;
  final ValueChanged<double> onSpeechRateChanged;
  // ==== Compression ====
  final String initialCompression;
  final ValueChanged<String> onCompressionChanged;
  // ==== Generate ====
  final Future<void> Function() onGenerateDigest;
  final Future<void> Function() onDownloadDigest;

  // Getting from main variables and sending them
  const DigestsScreen({
    super.key,
    // Getting
    required this.initialLanguage,
    required this.initialSpeechRate,
    required this.initialCompression,
    required this.onGenerateDigest,
    required this.onDownloadDigest,
    // Sending
    required this.onLanguageChanged,
    required this.onSpeechRateChanged,
    required this.onCompressionChanged,
  });

  @override
  State<DigestsScreen> createState() => _DigestsScreenState();
}

// Digest Screen
class _DigestsScreenState extends State<DigestsScreen> {
  // ====  Variables from main ==== 
  late String _selectedLanguage;
  late double _speechRate;
  late String _selectedCompression;

  // ==== Loading variables
  bool _isLoading = false;
  final Stopwatch _stopwatch = Stopwatch();
  Timer? _timer;
  String _elapsedTimer = '00:00';

  // ==== Dropdown variable(for checking incoming values) ====
  final List<String> _allowedLanguages = ["uk-UA", "en-US", "en-UK"]; 
  final List<String> _allowedCompression = [
  'Compressed(only main thought)', 
  'Detailed(3-4 sentences)'
]; 

  // ==== Other ====
  bool _toDownload = false;

  // Initializating variables through main
  @override
  void initState() {
    super.initState();

    _selectedLanguage = widget.initialLanguage;
    _speechRate = widget.initialSpeechRate;
    _selectedCompression = widget.initialCompression;
  }

  // Cleaning to prevent memory leak
  @override
  void dispose() {
    _timer?.cancel();

    super.dispose();
  }

  // Helper to start timer tracking
  void _startTimer() {
    _stopwatch.reset();
    _stopwatch.start();
    _timer = Timer.periodic(const Duration(milliseconds: 100), (timer){
      final elapsed = _stopwatch.elapsed;
      String twoTimes(int n) => n.toString().padLeft(2, '0');
      String minutes = twoTimes(elapsed.inMinutes.remainder(60));
      String seconds = twoTimes(elapsed.inSeconds.remainder(60));
      setState(() => _elapsedTimer = "$minutes:$seconds");
    });
  }

  // Helper to stop timer tracking
  void _stopTimer() {
    _stopwatch.stop();
    _timer?.cancel();
  }

  // UI
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black, 
      appBar: AppBar(
        title: const Text("Digest"),
        centerTitle: true,
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        // Body
        
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Compression
            const Text(
              "Compression level (level of details in digest)",
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
                  value: _selectedCompression,
                  dropdownColor: Colors.grey[900],
                  style: const TextStyle(color: Colors.white, fontSize: 16),
                  icon: const Icon(Icons.arrow_drop_down, color: Colors.blueAccent),
                  isExpanded: true,
                  items: _allowedCompression.map((String cmpr) {
                    String displayName = cmpr;
                    if (cmpr == 'Compressed(only main thought)') displayName = 'Only main thought';
                    if (cmpr == 'Detailed(3-4 sentences)') displayName = 'Detailed (3-4 sentences)';
                    
                    return DropdownMenuItem<String>(
                      value: cmpr, 
                      child: Text(displayName),
                    );
                  }).toList(),
                  onChanged: (String? newValue) {
                    if (newValue != null) {
                      setState(() => _selectedCompression = newValue);
                      // Sending update to main
                      widget.onCompressionChanged(newValue);
                    }
                  },
                ),
              ),
            ),

            const SizedBox(height: 30), 

            // Language
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
                      // Sending update to main
                      widget.onLanguageChanged(newValue);
                    }
                  },
                ),
              ),
            ),
            
            const SizedBox(height: 30), 

            // Speech rate
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
                // Sending update to main
                widget.onSpeechRateChanged(value); 
              },
            ),
            const SizedBox(height: 10),
            
            // Download conformation
            Text(
              "Do you want save it for local use?",
              style: const TextStyle(color: Colors.grey, fontSize: 14, fontWeight: FontWeight.bold),
            ),
            

            Checkbox(
              value: _toDownload,
              onChanged: (bool? value) async {
                if(value != null) {
                  
                  setState(() => _toDownload = value);
                  await widget.onDownloadDigest(); // using function from main
                   
                }
              } 
            ),

            const SizedBox(height: 30),

            // Generate area
            SizedBox(
              width: double.infinity,
              child: _isLoading
                  ? Column(
                      children: [
                        const CircularProgressIndicator(color: Colors.blueAccent),
                        const SizedBox(height: 12),
                        Text(
                          "Cooking digest... $_elapsedTimer",
                          style: const TextStyle(color: Colors.white70, fontSize: 16, fontWeight: FontWeight.w500),
                        ),
                      ],
                    )
                    : ElevatedButton(
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.blueAccent),
                      onPressed: () async {
                        setState(() => _isLoading = true);

                        // Starting timer for UI
                        _startTimer();

                        // Doing this with 'try' to use 'finally' which automatically will stop timer when action ends
                        try {
                          await widget.onGenerateDigest(); // using function from main
                        } finally {
                          _stopTimer();
                          if (mounted) setState(() => _isLoading = false);
                        }

                        if (!context.mounted) return;

                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Digest Generation triggered!")));

                        if (_toDownload) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Download triggered")));
                      },
                      child: const Text("Generate New Digest", style: TextStyle(color: Colors.white)),
                    ),
            ),
          ], 
        ), 
      ),

    );
  // UI
  } 
  
} // Digest Screen