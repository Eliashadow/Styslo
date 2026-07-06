import 'dart:convert';
import 'dart:async';
import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:http/http.dart' as http;
import 'package:vosk_flutter/vosk_flutter.dart';
import 'package:logger/logger.dart';

import 'audio_command_handler.dart';
import 'sources_screen.dart';
import 'settings_screen.dart';

late AudioCommandHandler globalAudioHandler;
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (const bool.fromEnvironment('dart.vm.product')) {
    Logger.level = Level.off; 
  }

  globalAudioHandler = await AudioService.init(
    builder: () => AudioCommandHandler(),
    config: const AudioServiceConfig(
      androidNotificationChannelId: 'com.styslo.channel.audio',
      androidNotificationChannelName: 'Audio Command Service',
      androidNotificationOngoing: true,
      androidShowNotificationBadge: true, // Note: ensure this matches your API version
    ),
  );
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
  final FlutterTts _flutterTts = FlutterTts();
  late AudioCommandHandler _audioHandler;

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
  bool _isIniatializing = false;
  String _recognizedText = 'waiting...';
  String _selectedCommandMode = 'button';
  final TextEditingController _commandController = TextEditingController();
  final VoskFlutterPlugin _vosk = VoskFlutterPlugin.instance();
  Model? _voskModel;
  Recognizer? _recognizer;
  SpeechService? _speechService;
  bool _isVoskReady = false;
  StreamSubscription? _voskSubscription;

  // ----TTS Settings----
  String _selectedLanguage = "uk-UA";
  double _speechRate = 0.5;
  bool _isPlaying = false;
  String _fetchedText =           "Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. "
                                  "Ut enim ad minim veniam, quis nostrud exercitation ullamco laboris nisi ut aliquip ex ea commodo consequat. "
                                  "Duis aute irure dolor in reprehenderit in voluptate velit esse cillum dolore eu fugiat nulla pariatur. "
                                  "Excepteur sint occaecat cupidatat non proident, sunt in culpa qui officia deserunt mollit anim id est laborum. ";
  int _currentWordOffset = 0;
  String _selectedCompression = "Compressed(only main thought)";
  int _currentWordLength = 0;
  int _speakBaseOffset = 0;


  // ----Log----
  final logger = Logger(
  printer: PrettyPrinter(
    methodCount: 0,       
    errorMethodCount: 5,  
    lineLength: 80,       
    colors: true,         
  ),
);

  @override
  void initState() {
    super.initState();
    _initVosk();
    _initAudioService();
    _initTts();
    _fetchConfig();
    
  }

  void _initTts() async {
    await _flutterTts.setLanguage(_selectedLanguage);
    await _flutterTts.setSpeechRate(_speechRate);
    await _flutterTts.setVolume(1.0);

    _flutterTts.setProgressHandler(
        (String text, int startOffset, int endOffset, String word) {
      setState(() {
        _currentWordOffset = _speakBaseOffset + startOffset;
        _currentWordLength = _speakBaseOffset + endOffset;
      });
    });

    _flutterTts.setStartHandler(() {
      setState(() => _isPlaying = true);
    });

    _flutterTts.setCompletionHandler(() {
      setState(() {
        _isPlaying = false;
        _currentWordOffset = 0;
        _speakBaseOffset = 0;
        _currentWordLength = 0;
      });
      _audioHandler.updatePlaybackState(false);
    });

    _flutterTts.setErrorHandler((msg) {
      setState(() => _isPlaying = false);
      _audioHandler.updatePlaybackState(false);
      logger.e("Error TTS: $msg");
    });
  }

  void _initVosk() async {
    logger.d("[VOSK DEBUG] Initializing Vosk model...");
    try{
      final modelPath = await ModelLoader().loadFromAssets('assets/models/uk.zip');
      _voskModel = await _vosk.createModel(modelPath);
      _recognizer = await _vosk.createRecognizer(model: _voskModel!, sampleRate: 16000);

      setState(() => _isVoskReady = true);
      logger.d("[VOSK DEBUG] Model initialized successfully.");
    } catch (e) {
      logger.d("[VOSK DEBUG] Error initializing Vosk model: $e");
    }
  }

Future<void> _initAudioService() async {
  _audioHandler = globalAudioHandler;
  
  final session = await AudioSession.instance;
  await session.configure(const AudioSessionConfiguration.speech());
  _audioHandler.onPauseTriggered = () async {
    logger.i('[HEADSET DEBUG] Pause callback fired');
    await _stop();
  };

  _audioHandler.onPlayTriggered = () async {
    logger.i('[HEADSET DEBUG] Play callback fired');
    await _speak(_fetchedText);
  };

  _audioHandler.onNextTriggered = () async {
    logger.i('[HEADSET DEBUG] Skipping and moving to next');
    await _switch();
  };

  _audioHandler.onPreviousTriggered = () async {
    logger.i('[HEADSET DEBUG] Skipping and moving to previous');
    await _switch();
  };
}

@override
void dispose() {
  _commandController.dispose(); 
  _voskSubscription?.cancel();
  _speechService?.stop();
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
    logger.e("Error fetching remote config: $e");
  }
}

  Future<void> _loadLiveNews() async {
    _currentWordOffset = 0;
    _speakBaseOffset = 0; 

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

    final session = await AudioSession.instance;
    await session.setActive(true);

    globalAudioHandler.mediaItem.add(MediaItem(
      id: 'styslo_tts_session',
      album: 'Styslo Reader',
      title: text.length > 30 ? '${text.substring(0, 30)}...' : text,
      artist: _currentChannel,
      duration: const Duration(hours: 1),
    ));

    _audioHandler.updatePlaybackState(true);

    await _updateTtsSettings();

    String textToSpeak = text;
    _speakBaseOffset = 0;
    if (_currentWordOffset > 0 && _currentWordOffset < text.length) {
      textToSpeak = text.substring(_currentWordOffset);
      _speakBaseOffset = _currentWordOffset;
    }
    await _flutterTts.speak(textToSpeak);
  }


  Future<void> _stop() async {
    _audioHandler.updatePlaybackState(false);
    await _flutterTts.stop();
    setState(() => _isPlaying = false);
  }

  Future<void> _stopVosk() async {
    logger.d('[VOSK DEBUG] Forcing hard stop of Vosk SpeechService...');
    
    if (_voskSubscription != null) {
      await _voskSubscription!.cancel();
      _voskSubscription = null;
      logger.i('[VOSK DEBUG] Stream subscription successfully canceled.');
    }

    if (_speechService != null) {
      try {
        await _speechService!.stop();
        logger.i('[VOSK DEBUG] Native speech service stopped.');
      } catch (e) {
        logger.e('[VOSK DEBUG] Error while stopping speech service: $e');
      }
    }

    setState(() => _isListening = false);

    await Future.delayed(const Duration(milliseconds: 200));
  }

Future<void> _listen() async {
  logger.d('[VOSK DEBUG] Received request to START mic. Current status: _isListening=$_isListening');

  if (_isIniatializing) {
    logger.d("[VOSK DEBUG] Already initializing, skipping start request");
    return;
  }

  if (_isListening) {
    logger.d("[VOSK DEBUG] Mic is already listening and service is active. Skipping.");
    return;
  }

  setState(() => _isIniatializing = true);

  try {

    if (!_isVoskReady || _recognizer == null) {
      logger.w("[VOSK DEBUG] Vosk is not ready yet.");
      return;
    }

    if (_speechService == null) {
      logger.d('[VOSK DEBUG] SpeechService does not exist. Creating a NEW instance...');
      _speechService = await _vosk.initSpeechService(_recognizer!);
    } else {
      logger.d('[VOSK DEBUG] SpeechService ALREADY exists. Reusing it...');
    }

    if (_voskSubscription != null) {
      logger.d('[VOSK DEBUG] Destroying subscription');
      await _voskSubscription!.cancel();
    }


    _voskSubscription = _speechService!.onResult().listen((jsonResult) {
      try {
        if (_selectedCommandMode == 'button') return;

        final Map<String, dynamic> parsed = json.decode(jsonResult);
        if (parsed.containsKey('text') && parsed['text'].toString().isNotEmpty) {
          String recognizedWords = parsed['text'].toString();
          logger.i("[VOSK DEBUG] Final result: $recognizedWords");

          setState(() => _recognizedText = recognizedWords);
          _executeCommand(recognizedWords);
        }
      } catch (e) {
        logger.e("[VOSK DEBUG] Cannot parse JSON: $e");
      }
    });

    logger.i('[VOSK DEBUG] Starting audio stream...');
    await _speechService!.start(); 
    
    setState(() => _isListening = true);

    logger.i('[VOSK DEBUG] Mic is successfully open and active.');

  } catch (e) {
      logger.e("[VOSK DEBUG] Cannot start audio stream: $e");
      setState(() => _isListening = false);
  } finally {
      setState(() => _isIniatializing = false);
      logger.i('[VOSK DEBUG] Initialization function finished.');
  }
}

Future<void> _switch() async {
  logger.i('Sometime there will be something');
}

  void _executeCommand(String text) async {
    String t = text.toLowerCase().replaceAll(RegExp(r'[^\w\sа-яА-ЯіІєЄїЇґҐ]'), '').trim();

    logger.d("[PARSER DEBUG] Command: '$t' | Mode: $_selectedCommandMode");

    if (_selectedCommandMode == 'button'){
      logger.d('[PARSER DEBUG] In button mode, so shutting down parser');
      return;
    }
    if (_selectedCommandMode == 'ok, styslo') {
      if (t.contains("окей стисло") || t.contains("ок стисло") || t.contains("hey styslo")) {
        t = t.replaceAll(RegExp(r'(окей стисло|ок стисло|hey styslo)'), '').trim();
        logger.i("[PARSER DEBUG] Wakeword found. Cleaned command: '$t'");
        if (t.isEmpty){
          logger.d('[PARSER DEBUG] Empty command after wakeword.');
          if (_fetchedText.isNotEmpty && _fetchedText != 'Loading news from source...'){
            await _speak(_fetchedText);
          } else {
            await _loadLiveNews();
          }
        }
      } else {
        logger.w("[PARSER DEBUG] Ignored: without wakeword.");
        return;
      }
    }

    if (t.contains("пауз") || t.contains("стоп") || t.contains("зупини") || t.contains("stop")) {
      logger.d('[PARSER DEBUG] Stop command recognized.');
      await _stop();
      return;
    }

    if (t.contains("читай") || t.contains("увімкни") || t.contains("запусти") || t.contains("play") || t.contains("старт")) {
       logger.d("[PARSER DEBUG] Play command recognized.");
       if (_fetchedText.isNotEmpty && _fetchedText != "Loading news from source...") {
         await _speak(_fetchedText);
         t = t.replaceAll(RegExp(r'(читай|увімкни|запусти|play|старт)'), '').trim(); 
       }
    }

    if (!_isConfigLoaded) {
      logger.e("[PARSER DEBUG] Error: Server config not loaded yet.");
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
          logger.d("[PARSER DEBUG] Category matched: '$catName' for trigger '$trigger'");
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
          logger.d("[PARSER DEBUG] Compression matched: '$compMode' for trigger '$trigger'");
          break compressionLoop;
        }
      }
    }

    if (nextChannel != _currentChannel || nextCompression != _selectedCompression){
      isChanged = true;
    }

    if(isChanged){
      logger.d("[PARSER DEBUG] Changes detected. Applying new settings: Channel: '$nextChannel', Compression: '$nextCompression'");
      setState(() {
      _currentChannel = nextChannel;
      _selectedCompression = nextCompression;
    }); 
      await _loadLiveNews();
    } else{
      logger.d("[PARSER DEBUG] No changes to apply.");
  
      if (_fetchedText.isNotEmpty && _fetchedText != "Loading news from source..." && _fetchedText != "Can't connect. Check backend") {
        await _speak(_fetchedText);
      } else {
        logger.w("[PARSER DEBUG] No text to speak. Current fetched text: '$_fetchedText'");
      }
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
                    onCommandModeChanged: (newMode) async {
                      setState(() => _selectedCommandMode = newMode);
                      await Future.microtask(() async {
                        try {
                        if (newMode == 'ok, styslo') {
                            logger.i("[DEBUG] Switched to 'ok, styslo'. Ensuring mic is fresh and starting...");
                            await _listen();
                        } else {
                            logger.i("[DEBUG] Switched to '$newMode'. Turning off Vosk completely.");
                            await _stopVosk();
                          }
                        } catch (e){
                          logger.e("[DEBUG] Error handling command mode change: $e");
                        }
                      });
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
                border: Border.all(color: Colors.blueAccent.withValues(alpha: 0.5)),
              ),
              child: Column(
                children: [
                  Text(
                    "Lorem Ipsum",
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 26,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.5,
                  ),
                  textAlign: TextAlign.center,
              ),

              const SizedBox(height: 24),

                  Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1E1E1E),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: Colors.blueAccent.withValues(alpha: 0.3)),
                      ),
                      child: Column(
                        children: [
                          _fetchedText.isNotEmpty
                              ? RichText(
                                  text: TextSpan(
                                    style: const TextStyle(color: Colors.white, fontSize: 16, height: 1.6),
                                    children: [
                                      TextSpan(
                                        text: _fetchedText.substring(0, _currentWordOffset.clamp(0, _fetchedText.length)),
                                      ),

                                      TextSpan(
                                        text: _fetchedText.substring(_currentWordOffset.clamp(0, _fetchedText.length), _currentWordLength.clamp(0, _fetchedText.length)),
                                        style: const TextStyle(
                                          color: Colors.black,
                                          backgroundColor: Colors.yellowAccent, 
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      TextSpan(
                                        text: _fetchedText.substring(_currentWordLength.clamp(0, _fetchedText.length)),
                                      ),
                                    ],
                                  ),
                                )
                              : const Text(
                                  "Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. "
                                  "Ut enim ad minim veniam, quis nostrud exercitation ullamco laboris nisi ut aliquip ex ea commodo consequat. "
                                  "Duis aute irure dolor in reprehenderit in voluptate velit esse cillum dolore eu fugiat nulla pariatur. "
                                  "Excepteur sint occaecat cupidatat non proident, sunt in culpa qui officia deserunt mollit anim id est laborum. ",
                                  style: TextStyle(color: Colors.white70, fontSize: 15),
                                ),
                          
                          const SizedBox(height: 20),

              Column(
                  children: [
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
                            const SizedBox(height: 50),

              
                      // ---- OK, STYSLO (background mode) ----
                      if (_selectedCommandMode == 'ok, styslo') ...[
                        const Text(
                          "\"Okay, Styslo\" is now active!", 
                          style: TextStyle(color: Colors.tealAccent, fontWeight: FontWeight.bold),
                        ),
                      ],
                    
                      const SizedBox(height: 40),

                    Text(
                          "DEBUG Listened: \"$_recognizedText\"",
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 18, fontStyle: FontStyle.italic, color: Colors.amberAccent),
                        ),
                      const SizedBox(height: 40),

                    Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        mainAxisSize: MainAxisSize.min, 
                        children: [
                            IconButton(
                                  iconSize: 36,
                                  icon: const Icon(Icons.skip_previous, color: Colors.blueAccent),
                                  onPressed: () {
                                    logger.d("[DEBUG UI] Skip backward pressed");
                                  },
                                ),
                            const SizedBox(width: 24),
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
                                  const SizedBox(width: 20),
                                  IconButton(
                                      iconSize: 36,
                                      icon: const Icon(Icons.skip_next, color: Colors.blueAccent),
                                      onPressed: () {
                                            logger.d("[DEBUG UI] Skip forward pressed");
                                    },
                                  ),
                                ],
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
      ),
    );
  } 
} 