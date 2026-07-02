import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:flutter_tts/flutter_tts.dart';
import 'package:http/http.dart' as http;

import 'sources_screen.dart';
import 'settings_screen.dart';

void main() {
  runApp(const StysloApp());
}

class StysloApp extends StatelessWidget {
  const StysloApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Styslo',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: Colors.black,
        primaryColor: Colors.blueAccent,
      ),
      home: const PlayerScreen(),
    );
  }
}

class PlayerScreen extends StatefulWidget {
  const PlayerScreen({super.key});

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  late stt.SpeechToText _speech;
  final FlutterTts _flutterTts = FlutterTts();

  // ----Categories----
  String _currentChannel = "General"; 
  List<String> _dynamicCategories = ["General"]; 
  bool _isCategoriesLoading = true;

// ----Server related----
  final String _apiBaseUrl = "http://192.168.1.101:8000/api";
  Map<String, dynamic> _remoteCategories = {};
  Map<String, dynamic> _remoteCompression = {};
  bool _isConfigLoaded = false;

  // ----Intent parser----
  bool _isListening = false;
  String _recognizedText = 'waiting...';
  String _selectedCommandMode = 'voice';
  final TextEditingController _commandController = TextEditingController();

  // ----TTS Settings----
  String _selectedLanguage = "uk-UA";
  double _speechRate = 0.5;
  bool _isPlaying = false;
  String _fetchedText = 'Waiting';
  int _currentWordOffset = 0;
  String _selectedCompression = "Compressed(only main thought)";

  
  @override
  void initState() {
    super.initState();
    _speech = stt.SpeechToText();
    _initTts();
    _fetchConfig();
    
  }

  void _initTts() async {
    await _flutterTts.setLanguage(_selectedLanguage);
    await _flutterTts.setSpeechRate(_speechRate);
    await _flutterTts.setVolume(1.0);

    _flutterTts.setProgressHandler((String text, int startOffset, int endOffset, String word) {
      _currentWordOffset = startOffset;
    });

    _flutterTts.setStartHandler(() {
      setState(() => _isPlaying = true);
    });

    _flutterTts.setCompletionHandler(() {
      setState(() {
        _isPlaying = false;
        _currentWordOffset = 0;
      });
    });

    _flutterTts.setErrorHandler((msg) {
      setState(() => _isPlaying = false);
      print("Error TTS: $msg");
    });
  }

@override
void dispose() {
  _commandController.dispose(); 
  super.dispose();
}

  Future<void> _updateTtsSettings() async {
    await _flutterTts.setLanguage(_selectedLanguage);
    await _flutterTts.setSpeechRate(_speechRate);
  }

Future<void> _fetchConfig() async {
  try {
    final response = await http.get(Uri.parse("$_apiBaseUrl/config"));
    if (response.statusCode == 200) {
      final Map<String, dynamic> data = json.decode(utf8.decode(response.bodyBytes));
      
      setState(() {
        _remoteCategories = data["categories"] ?? {};
        _remoteCompression = data["compression"] ?? {};
        
        _dynamicCategories = _remoteCategories.keys.toList();
        
        if (_dynamicCategories.isNotEmpty && !_dynamicCategories.contains(_currentChannel)) {
          _currentChannel = _dynamicCategories.first;
        }
        _isCategoriesLoading = false;
        _isConfigLoaded = true;
      });
    }
  } catch (e) {
    print("Error fetching remote config: $e");
  }
}

  Future<void> _loadLiveNews() async {
    _currentWordOffset = 0;

    setState(() {
      _fetchedText = "Loading news from source...";
    });

    try {
      final String backendUrl = "$_apiBaseUrl/news";

      final response = await http.post(
        Uri.parse(backendUrl),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "category": _currentChannel,
          "compression": _selectedCompression, 
        }),
      );

      if (response.statusCode == 200) {
        final Map<String, dynamic> data = json.decode(utf8.decode(response.bodyBytes));
        setState(() {
          _fetchedText = data["content"] ?? "Text is None";
        });
      } else {
        setState(() => _fetchedText = "Server error: ${response.statusCode}");
      }
    } catch (e) {
      setState(() => _fetchedText = "Can't connect. Check backend");
    }

    if (_isPlaying) {
      _speak(_fetchedText);
    }
  }

  Future<void> _speak(String text) async {
    if (text.isEmpty) return;
    await _updateTtsSettings();

    String textToSpeak = text;
    if (_currentWordOffset > 0 && _currentWordOffset < text.length) {
      textToSpeak = text.substring(_currentWordOffset);
    }
    await _flutterTts.speak(textToSpeak);
  }

  Future<void> _stop() async {
    await _flutterTts.stop();
    setState(() => _isPlaying = false);
  }

void _listen() async {
  if (_isListening && _selectedCommandMode == 'ok, styslo') return;

  if (!_isListening) {
    if (_isPlaying && _selectedCommandMode != 'ok, styslo') {
      await _stop();
    }

    await _speech.stop();

    bool available = await _speech.initialize(
      onStatus: (status) {
        print('Speech Status: $status');
        
        if (status == 'notListening' && _selectedCommandMode == 'ok, styslo') {
          Future.delayed(const Duration(seconds: 1), () {
            if (_selectedCommandMode == 'ok, styslo' && !_isListening) {
              print('[DEBUG] Restarting listening for "ok, styslo" mode...');
              _listen(); 
            }
          });
        }
      },
      onError: (errorNotification) {
        print('Speech Error: $errorNotification');
        if (_selectedCommandMode == 'ok, styslo') {
          setState(() => _isListening = false);
          Future.delayed(const Duration(seconds: 1), () => _listen());
        }
      },
    );

    if (available) {
      setState(() => _isListening = true);
      
      _speech.listen(
        listenFor: const Duration(seconds: 30), 
        pauseFor: const Duration(seconds: 10),
        localeId: _selectedLanguage,
        onResult: (val) {
          setState(() {
            _recognizedText = val.recognizedWords;
          });
          
          if (val.finalResult) {
            print('[DEBUG] final text recognized: $_recognizedText');
            setState(() => _isListening = false);
            _executeCommand(_recognizedText);
          }
        },
      );
    }
  } else {
    setState(() => _isListening = false);
    _speech.stop();
  }
}

  void _executeCommand(String text) async {
    String t = text.toLowerCase().replaceAll(RegExp(r'[^\w\sа-яА-ЯіІєЄїЇґҐ]'), '').trim();

    print("[PARSER DEBUG] Command: '$t' | Mode: $_selectedCommandMode");

    if (_selectedCommandMode == 'ok, styslo') {
    if (t.contains("окей стисло") || t.contains("ок стисло") || t.contains("hey styslo")) {
      t = t.replaceAll(RegExp(r'(окей стисло|ок стисло|hey styslo)'), '').trim();
      print("[PARSER DEBUG] Wakeword found. Cleaned command: '$t'");
    } else {
      print("[PARSER DEBUG] Ignored: without wakeword.");
      return;
    }
  }

    if (t.contains("пауз") || t.contains("стоп") || t.contains("зупини") || t.contains("stop")) {
      await _stop();
      return;
    }

    if (!_isConfigLoaded) {
      print("[PARSER DEBUG] Error: Server config not loaded yet.");
      return;
    } 

    String nextChannel = _currentChannel;
    String nextCompression = _selectedCompression;
    bool isChanged = false;

    categoryLoop:
    for (var entry in _remoteCategories.entries) {
      String catName = entry.key;
      List<dynamic> triggers = entry.value;

      for (var trigger in triggers) {
        if (t.contains(trigger.toString().toLowerCase())) {
          nextChannel = catName;
          print("[PARSER DEBUG] Category matched: '$catName' for trigger '$trigger'");
          break categoryLoop;
        }
      }
    }

    compressionLoop:
    for (var entry in _remoteCompression.entries) {
      String compMode = entry.key;
      List<dynamic> triggers = entry.value;

      for (var trigger in triggers) {
        if (t.contains(trigger.toString().toLowerCase())) {
          nextCompression = compMode;
          print("[PARSER DEBUG] Compression matched: '$compMode' for trigger '$trigger'");
          break compressionLoop;
        }
      }
    }

    if (nextChannel != _currentChannel || nextCompression != _selectedCompression){
      isChanged = true;
    }

    if(isChanged){
      print("[PARSER DEBUG] Changes detected. Applying new settings: Channel: '$nextChannel', Compression: '$nextCompression'");
      setState(() {
      _currentChannel = nextChannel;
      _selectedCompression = nextCompression;
    }); 
      await _loadLiveNews();
    } else{
      print("[PARSER DEBUG] No changes to apply.");
    }
    
      if (_fetchedText.isNotEmpty && _fetchedText != "Loading news from source..." && _fetchedText != "Can't connect. Check backend") {
        await _speak(_fetchedText);
      } else {
        print("[PARSER DEBUG] No text to speak. Current fetched text: '$_fetchedText'");
      }
    
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Styslo'),
        centerTitle: true,
        backgroundColor: Colors.black,
        actions: [
          IconButton(
            icon: const Icon(Icons.settings, color: Colors.blueAccent),
            tooltip: "Settings",
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => SettingsScreen(
                    initialLanguage: _selectedLanguage,
                    initialSpeechRate: _speechRate,
                    initialCommandMode: _selectedCommandMode,
                    onCommandModeChanged: (newMode) {
                      setState(() => _selectedCommandMode = newMode);

                      if (newMode == 'ok, styslo') {
                      print("[DEBUG] Main got Wake-word. Starting mic up...");
                      Future.delayed(const Duration(milliseconds: 300), () {
                        _listen(); 
                      });
                    } else {
                      print("[DEBUG] Exiting styslo, ok shutting down mic.");
                      _speech.stop();
                      setState(() => _isListening = false);
                    }
                    },
                    onLanguageChanged: (newLang) {
                      setState(() => _selectedLanguage = newLang);
                    },
                    onSpeechRateChanged: (newRate) {
                      setState(() => _speechRate = newRate);
                      _updateTtsSettings();
                    },
                    
                  ),
                ),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.list_alt, color: Colors.blueAccent),
            tooltip: "Source manager",
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const SourcesScreen()),
              ).then((_) {
                _fetchConfig();
              });
            },
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: const Color(0xFF1E1E1E),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.blueAccent.withOpacity(0.5)),
              ),
              child: Column(
                children: [
                  GestureDetector(
                    onTap: () {
                      setState(() {
                        _isPlaying = !_isPlaying;
                      });

                      if (_isPlaying) {
                        _speak(_fetchedText);
                      } else {
                        _stop();
                      }
                    },
                    child: CircleAvatar(
                      radius: 45,
                      backgroundColor: _isPlaying ? Colors.red : Colors.blueAccent,
                      child: Icon(
                        _isPlaying ? Icons.pause : Icons.play_arrow,
                        size: 40,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  const SizedBox(height: 15),
                  _isCategoriesLoading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : DropdownButton<String>(
                          value: _currentChannel,
                          dropdownColor: Colors.black,
                          style: const TextStyle(color: Colors.white, fontSize: 16),
                          icon: const Icon(Icons.arrow_drop_down, color: Colors.blueAccent),
                          items: _dynamicCategories.map<DropdownMenuItem<String>>((String value) {
                            return DropdownMenuItem<String>(
                              value: value,
                              child: Text(value),
                            );
                          }).toList(),
                          onChanged: (String? newValue) {
                            if (newValue != null) {
                              setState(() {
                                _currentChannel = newValue;
                              });
                              _loadLiveNews();
                            }
                          },
                        ),
                  const SizedBox(height: 20),
          Text(
            "Listened: \"$_recognizedText\"",
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 18, fontStyle: FontStyle.italic, color: Colors.amberAccent),
          ),
          const SizedBox(height: 50),

          //  VOICE (mic) ----
          if (_selectedCommandMode == 'voice') ...[
            GestureDetector(
              onTap: _listen,
              child: CircleAvatar(
                radius: 45,
                backgroundColor: _isListening ? Colors.red : Colors.blueAccent,
                child: Icon(
                  _isListening ? Icons.mic : Icons.mic_none,
                  size: 40,
                  color: Colors.white,
                ),
              ),
            ),
            const SizedBox(height: 15),
            Text(
              _isListening ? "Listening..." : "Press me", 
              style: const TextStyle(color: Colors.white54),
            ),
          ],

          // ---- OK, STYSLO (background mode) ----
          if (_selectedCommandMode == 'ok, styslo') ...[
            const CircleAvatar(
              radius: 45,
              backgroundColor: Colors.teal,
              child: Icon(
                Icons.record_voice_over, 
                size: 40,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 15),
            const Text(
              "Background mode: say  \"Okay, Styslo\"", 
              style: TextStyle(color: Colors.tealAccent, fontWeight: FontWeight.bold),
            ),
          ],

          // ----  TEXT ----
          if (_selectedCommandMode == 'text')
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 12.0),
              child: Row(
                children: [
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.grey[900],
                        borderRadius: BorderRadius.circular(30),
                        border: Border.all(color: Colors.blueAccent.withOpacity(0.4)),
                      ),
                      child: TextField(
                        controller: _commandController,
                        style: const TextStyle(color: Colors.white),
                        decoration: const InputDecoration(
                          hintText: "Enter command (e.g., sports detailed)...",
                          hintStyle: TextStyle(color: Colors.grey, fontSize: 14),
                          contentPadding: EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                          border: InputBorder.none,
                        ),
                        onSubmitted: (value) {
                          if (value.trim().isNotEmpty) {
                            _executeCommand(value);
                            _commandController.clear();
                          }
                        },
                      ),
                    ),
                  ),

                  const SizedBox(width: 8),
                  CircleAvatar(
                    backgroundColor: Colors.blueAccent,
                    radius: 24,
                    child: IconButton(
                      icon: const Icon(Icons.send, color: Colors.white, size: 20),
                      onPressed: () {
                        if (_commandController.text.trim().isNotEmpty) {
                          _executeCommand(_commandController.text);
                          _commandController.clear();
                        }
                      },
                    ),
                  ),
                ],
              ),
            ),

                  const SizedBox(height: 30),
                ],
              ),
            ),
          ]
        )
      ),
    ); 
  }
} 