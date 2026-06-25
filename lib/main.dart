import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:flutter_tts/flutter_tts.dart';
import 'package:http/http.dart' as http;
import 'package:dart_rss/dart_rss.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  runApp(const StysloApp());
}

class StysloApp extends StatelessWidget {
  const StysloApp({super.key});


  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Styslo',
      theme: ThemeData.dark().copyWith(
      primaryColor: Colors.blueAccent,
      scaffoldBackgroundColor: const Color(0xFF121212)
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
  late FlutterTts _flutterTts; 
  
  // --- Settings Intent Parser ---
  bool _isListening = false;
  String _recognizedText = "Press me to start";

  String _fetchedText = "Loading";

  // --- Settings TTS ---
  String _selectedLanguage = "en-UK";
  double _speechRate = 0.5;           // Rate (0.0 - 1.0)
  double _volume = 1.0;               // Volume (0.0 - 1.0)
  String _currentChannel = "General";
  String _compressionLevel = "Normal";
  bool _isPlaying = false; 
  Map<String, String> _customRssUrls = {
    "General": "http://feeds.bbci.co.uk/news/rss.xml",
    "Sport ⚽": "https://tsn.ua/rss/sport.rss",
    "Tecnologies 💻": "https://tsn.ua/rss/science.rss",
    "Politics 🏛️": "https://tsn.ua/rss/politics.rss",
  };

  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _urlController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _speech = stt.SpeechToText();
    _initTts();
    _loadCustomSources();
  }


 void _initTts() async{
  _flutterTts = FlutterTts();
  _updateTtsSettings();
 }

 void _updateTtsSettings() async {
    await _flutterTts.setLanguage(_selectedLanguage);
    await _flutterTts.setSpeechRate(_speechRate);
    await _flutterTts.setVolume(_volume);
  }

Future<void> _loadCustomSources() async {
    final prefs = await SharedPreferences.getInstance();
    final List<String>? savedChannels = prefs.getStringList('channels_list');
    
    if (savedChannels != null && savedChannels.isNotEmpty) {
      Map<String, String> loadedUrls = {};
      for (String channel in savedChannels) {
        String? url = prefs.getString('rss_$channel');
        if (url != null) {
          loadedUrls[channel] = url;
        }
      }
      setState(() {
        _customRssUrls = loadedUrls;
        if (!_customRssUrls.containsKey(_currentChannel)) {
          _currentChannel = _customRssUrls.keys.first;
        }
      });
    }
    _loadLiveNews();
  }

  // --- Saving new source ---
  Future<void> _addCustomSource(String name, String url) async {
    if (name.isEmpty || url.isEmpty) return;

    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _customRssUrls[name] = url;
    });

    await prefs.setString('rss_$name', url);
    await prefs.setStringList('channels_list', _customRssUrls.keys.toList());
    
    _nameController.clear();
    _urlController.clear();
    
    _loadLiveNews();
  }

  Future<void> _loadLiveNews() async {
    setState(() {
      _fetchedText = "Loading new news from sources...";
    });

    try {
      final url = _customRssUrls[_currentChannel] ?? _customRssUrls.values.first;
      final response = await http.get(Uri.parse(url));

      if (response.statusCode == 200) {
        final feed = RssFeed.parse(response.body);
        if (feed.items != null && feed.items!.isNotEmpty) {
          final latest = feed.items!.first;
          setState(() {
            if (_compressionLevel == "Compressed(only main thought)") {
              _fetchedText = latest.title ?? "Header is empty";
            } else {
              _fetchedText = "${latest.title}. ${latest.description ?? ''}";
            }
          });
        } else {
          setState(() => _fetchedText = "There is no new news.");
        }
      } else {
        setState(() => _fetchedText = "Server problem RSS.");
      }
    } catch (e) {
      setState(() => _fetchedText = "Error of loading data.");
    }

    if (_isPlaying) {
      _speak(_fetchedText);
    }
  }

 void _speak(String text) async {
  if (_isPlaying){
    _updateTtsSettings();
    await _flutterTts.speak(text);
  } 
 }

 void _stopSpeaking() async {
    await _flutterTts.stop();
  }

void _listen() async {
    if (!_isListening) {
      if (_isPlaying) {
        setState(() => _isPlaying = false);
        _stopSpeaking();
      }

      bool available = await _speech.initialize(
        onStatus: (val) => print('Status: $val'),
        onError: (val) => print('Error: $val'),
      );
      if (available) {
        setState(() => _isListening = true);
        _speech.listen(
        localeId: _selectedLanguage,
          onResult: (val) => setState(() {
            _recognizedText = val.recognizedWords;
            if (val.finalResult) {
              _isListening = false;
              _executeCommand(_recognizedText);
            }
          }),
        );
      }
    } else {
      setState(() => _isListening = false);
      _speech.stop();
    }
  }

  // Intent Parser
  void _executeCommand(String text) async {
    String t = text.toLowerCase();

    if (t.contains("пауз") || t.contains("стоп") || t.contains("зупини")) {
      setState(() => _isPlaying = false);
      _stopSpeaking();
      return;
    }
    String nextChannel = _currentChannel;
    String nextCompression = _compressionLevel;
    bool shouldPlay = _isPlaying;

    if (t.contains("play") || t.contains("вруби") || t.contains("увімкни") || t.contains("слухати")) {
      shouldPlay = true;
    }

    for (String channelName in _customRssUrls.keys) {
      if (t.contains(channelName.toLowerCase().replaceAll(RegExp(r'[^\w\sа-яА-ЯіІєЄїЇґҐ]'), ''))) {
        nextChannel = channelName;
        shouldPlay = true;
        break;
      }
    }

    if (t.contains("коротко") || t.contains("стисло") || t.contains("головне")) {
      nextCompression = "Compressed(only main thought)";
    } else if (t.contains("детальн") || t.contains("детальніше")) {
      nextCompression = "Detailed";
    }

    setState(() {
      _currentChannel = nextChannel;
      _compressionLevel = nextCompression;
      _isPlaying = shouldPlay;
    });

    await _loadLiveNews();
  }

  @override
  void dispose() {
    _flutterTts.stop();
    super.dispose();
  }

void _showAddSourceDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: const Text("Add your source"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(labelText: "Name"),
            ),
            TextField(
              controller: _urlController,
              decoration: const InputDecoration(labelText: "Link"),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            onPressed: () {
              _addCustomSource(_nameController.text, _urlController.text);
              Navigator.pop(context);
            },
            child: const Text("Add"),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final List<String> allowedLanguages = ["uk-UA", "en-US", "en-UK"];
    if (!allowedLanguages.contains(_selectedLanguage)) {
      _selectedLanguage = "uk-UA";
    }
    return Scaffold(
      appBar: AppBar(
        title: const Text('Styslo'),
        centerTitle: true,
        backgroundColor: Colors.black,
        actions: [
          IconButton(
            icon: const Icon(Icons.add_circle_outline, color: Colors.blueAccent),
            onPressed: _showAddSourceDialog,
          )
        ],
      ),
      body: SingleChildScrollView( 
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // --- Player screen---
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
                        _isPlaying = !_isPlaying; // Перемикаємо стан плеєра
                      });
                      
                      if (_isPlaying) {
                        // Якщо натиснули Play — запускаємо озвучення поточних новин
                        _speak(_fetchedText);
                      } else {
                        // Якщо натиснули Pause — глушимо TTS голоси
                        _stopSpeaking();
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

                  DropdownButton<String>(
                    value: _customRssUrls.containsKey(_currentChannel) ? _currentChannel : _customRssUrls.keys.first,
                    dropdownColor: const Color(0xFF1E1E1E),
                    style: const TextStyle(fontSize: 22, color: Colors.white),
                    items: _customRssUrls.keys.map((String channel) {
                      return DropdownMenuItem<String>(
                        value: channel,
                        child: Text(channel),
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
                  const SizedBox(height: 10),

                  Text("Compression level: $_compressionLevel", style: const TextStyle(fontSize: 14, color: Colors.white70), textAlign: TextAlign.center),
                ],
              ),
            ),
            const SizedBox(height: 25),
            
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF1A1A1A),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  // Language selection
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text("Language:"),
                      DropdownButton<String>(
                        value: _selectedLanguage,
                        dropdownColor: const Color(0xFF1E1E1E),
                        items: const [
                          DropdownMenuItem(value: "uk-UA", child: Text("Українська 🇺🇦")),
                          DropdownMenuItem(value: "en-US", child: Text("English 🇺🇸")),
                          DropdownMenuItem(value: "en-UK", child: Text("English (UK) 🇬🇧")),
                        ],
                        onChanged: (String? newLang) {
                          if (newLang != null) {
                            setState(() {
                              _selectedLanguage = newLang;
                            });
                            _updateTtsSettings();
                          }
                        },
                      ),
                    ],
                  ),
                  const Divider(color: Colors.white24),
                  
                  // Rate slider
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text("Speech rate: ${_speechRate.toStringAsFixed(1)}"),
                      Slider(
                        value: _speechRate,
                        min: 0.1,
                        max: 1.0,
                        activeColor: Colors.blueAccent,
                        onChanged: (value) {
                          setState(() => _speechRate = value);
                          _updateTtsSettings();
                        },
                      ),
                    ],
                  ),
                  
                  // Loudness slider
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text("Volume: ${(_volume * 100).toInt()}%"),
                      Slider(
                        value: _volume,
                        min: 0.0,
                        max: 1.0,
                        activeColor: Colors.greenAccent,
                        onChanged: (value) {
                          setState(() => _volume = value);
                          _updateTtsSettings();
                        },
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 25),

            Text(
              "Listened: \"$_recognizedText\"",
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 18, fontStyle: FontStyle.italic, color: Colors.amberAccent),
            ),
            const SizedBox(height: 50),
            
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
            Text(_isListening ? "Listening..." : "Press me", style: const TextStyle(color: Colors.white54)),
          ],
        ),
      ),
    );
  }
}