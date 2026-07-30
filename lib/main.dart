// ----Essential imports----
import 'dart:convert';
import 'package:flutter/material.dart';

// ----Audio imports----
import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:just_audio/just_audio.dart';

// ----Internet imports----
import 'package:http/http.dart' as http;
import 'package:connectivity_plus/connectivity_plus.dart';
import 'dart:async';

// ----Offline imports----
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';

// ----Ok, Styslo imports----
import 'package:vosk_flutter/vosk_flutter.dart';

// ----Logs import----
import 'package:logger/logger.dart';

// ----Other screens imports----
import 'audio_command_handler.dart';
import 'sources_screen.dart';
import 'settings_screen.dart';
import 'local_database.dart';

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
      androidShowNotificationBadge: true, 
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
  final AudioPlayer _audioPlayer = AudioPlayer();
  late AudioCommandHandler _audioHandler;

  // ----Categories----
  String _currentChannel = "General"; 
  List<String> _dynamicCategories = ["General"]; 
  bool _isCategoriesLoading = true;

  // ----Internet related----
  final String _apiBaseUrl = "http://192.168.1.126:8000/api";
  Map<String, dynamic> _remoteCategories = {};
  Map<String, dynamic> _remoteCompression = {};
  bool _isConfigLoaded = false;
  StreamSubscription<List<ConnectivityResult>>? _subscription;
  bool _isOnline = false;

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

  // ----Audio Player Settings----
  String _currentTitle = 'Lorem Ipsum';
  String _selectedLanguage = "uk-UA";
  double _speechRate = 0.5;
  bool _isPlaying = false;
  String _selectedCompression = "Compressed(only main thought)";
  List<Map<String, dynamic>> _wordTimings = [];
  int _currentlyHighlightedIndex = -1;
  String _audioUrl = '';


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
    _initAudioPlayer();
    _checkConnect();
  }

  void _initAudioPlayer() async {
  _audioPlayer.positionStream.listen((position) {
    int milliseconds = position.inMilliseconds;
    double currentSeconds = milliseconds / 1000.0;

    int newIndex = _wordTimings.indexWhere((timing) {
      double start = timing['Start']; 
      double end = timing['End'];

      return currentSeconds >= start && currentSeconds <= end; 
  });

  if (newIndex != -1 && newIndex != _currentlyHighlightedIndex) {
    setState(() {
      _currentlyHighlightedIndex = newIndex;
      });
    }
  });
}

  void _initVosk() async {
    logger.d("[VOSK] Initializing Vosk model...");
    try{
      final modelPath = await ModelLoader().loadFromAssets('assets/models/voice/uk.zip');
      _voskModel = await _vosk.createModel(modelPath);
      _recognizer = await _vosk.createRecognizer(model: _voskModel!, sampleRate: 16000);

      setState(() => _isVoskReady = true);
      logger.d("[VOSK] Model initialized successfully.");
    } catch (e) {
      logger.d("[VOSK] Error initializing Vosk model: $e");
    }
  }

  Future<void> _initAudioService() async {
    _audioHandler = globalAudioHandler;

    final session = await AudioSession.instance;
    await session.setActive(true);
    await session.configure(const AudioSessionConfiguration.speech());

    _audioHandler.onPauseTriggered = () async {
      logger.i('[HEADSET] Playing status in init: $_isPlaying');
      logger.i('[HEADSET] Pause callback fired');
      await _stop();
    };

    _audioHandler.onPlayTriggered = () async {
      logger.i('[HEADSET] Playing status in init: $_isPlaying ');
      logger.i('[HEADSET] Play callback fired');
      await _speak(_audioUrl);
    };

    _audioHandler.onNextTriggered = () async {
      await _switch();
    };

    _audioHandler.onPreviousTriggered = () async {
      await _switch();
    };
  }

  @override
  void dispose() {
    _audioHandler.onPlayTriggered = null;
    _audioHandler.onPauseTriggered = null;
    _audioHandler.onNextTriggered = null;
    _audioHandler.onPreviousTriggered = null;

    _commandController.dispose();

    _voskSubscription?.cancel();
    _speechService?.stop();
    _subscription?.cancel();
    super.dispose();
  }

  Future<void> _checkConnect() async {
    try {
      _subscription = Connectivity().onConnectivityChanged.listen((List<ConnectivityResult> results) async {
        // Check if there is any physical connection at all (Wi-Fi or mobile data)
        if (results.contains(ConnectivityResult.none)) {
          logger.w("[NETWORK] Network is missing. Switching to offline mode.");
          setState (() => _isOnline = false);
          // Offline mode(loading from local DB)
          await _fetchConfig();

        } else {
          // Check if server is reachable
          try {
            final response = await http.get(Uri.parse("$_apiBaseUrl/config")).timeout(const Duration(seconds: 5));
            
            if (response.statusCode == 200) {
              logger.i("[NETWORK] Internet is available, server is reachable.");
              setState (() => _isOnline = true);
              await _fetchConfig();
            } else {
              logger.w("[NETWORK] Internet is available, but server returned an error: ${response.statusCode}");
              setState (() => _isOnline = false);
              await _fetchConfig();
            }
          } catch (serverError) {
            // Server is down or unreachable on the local network
            logger.e("[NETWORK] Server is unreachable: $serverError. Switching to offline mode.");
            setState (() => _isOnline = false);
            await _fetchConfig();
          }
        }
      });
    } catch (e) {
      logger.e("Error subscribing to network changes: $e");
    }
  }

  Future<void> _fetchConfig() async {
    await _loadPreferences();

    if (_isOnline == true) {
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

          // Saving categories into database
          await LocalDatabase.instance.saveCategories(_dynamicCategories);
          return;
        }
      } catch (e) {
        logger.e("Error fetching remote config: $e");
      }
    }
    // If there is not internet or error in fetching
    final localCategories = await LocalDatabase.instance.getCategories();
    setState(() {
      if (localCategories.isNotEmpty) {
        _dynamicCategories = localCategories;
        if (!_dynamicCategories.contains(_currentChannel)) {
          _currentChannel = _dynamicCategories.first;
        }
    }
    _isCategoriesLoading = false;
    _isConfigLoaded = localCategories.isNotEmpty;
    });
  }

  Future<void> _savePreferences() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('speech_rate', _speechRate);
    await prefs.setString('selected_language', _selectedLanguage);
    await prefs.setString('current_channel', _currentChannel);
  }

  Future<void> _loadPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _speechRate = prefs.getDouble('speech_rate') ?? 0.5;
      _selectedLanguage = prefs.getString('selected_language') ?? 'uk-UA';
      _currentChannel = prefs.getString('current_channel') ?? 'General';
    });
  }

  Future<void> downloadCategoryOffline(String categoryName) async {
    try {
      logger.i("Starting download for category: $categoryName");

      // Asking backend to get news/audio
      final response = await http.post(
        Uri.parse("$_apiBaseUrl/news"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "category": categoryName,
          "compression": _selectedCompression,
          "language": _selectedLanguage,
          "speech_rate": _speechRate,
          "title": "",
        }),
      );

      if (response.statusCode == 200) {
        final data = json.decode(utf8.decode(response.bodyBytes));
        final String remoteAudioUrl = data['audio_url'];
        final String title = data['title'] ?? '';
        final String content = data['content'] ?? '';
        final List<dynamic> timings = data['timings'] ?? [];

        // Downloading audio from server
        final audioResponse = await http.get(Uri.parse(remoteAudioUrl));
        if (audioResponse.statusCode == 200) {
          // Getting local dir of app
          final directory = await getApplicationDocumentsDirectory();
          final fileName = "${categoryName.hashCode}_${DateTime.now().millisecondsSinceEpoch}.wav";
          final localFile = File('${directory.path}/$fileName');

          // Saving audio as bytes
          await localFile.writeAsBytes(audioResponse.bodyBytes);

          //  Saving data in local DB(sqflite)
          await LocalDatabase.instance.saveArticle(
            category: categoryName,
            title: title,
            content: content,
            audioPath: localFile.path, // Saving local path except link
            timingsJson: jsonEncode(timings),
          );

          logger.i("Successfully cached category '$categoryName' offline.");
        }
      }
    } catch (e) {
      logger.e("Error downloading category for offline: $e");
    }
  }

  Future<void> _loadOrGoOffline() async {
    if (_isOnline){
      await _loadLiveNews();
    } else {
      // Offline: reading DB
      logger.i("Offline mode: Loading category '$_currentChannel' from local DB...");
      final cachedArticle = await LocalDatabase.instance.getArticleForCategory(_currentChannel);

      if (cachedArticle != null) {
        setState(() {
          _currentTitle = cachedArticle['title'];
          _audioUrl = cachedArticle['audio_path']; // Path to audio on device
          _wordTimings = List<Map<String, dynamic>>.from(json.decode(cachedArticle['timings']));
        });
        logger.i("Loaded offline audio path: $_audioUrl");
      } else {
        logger.w("No cached data found for this category offline.");
      }
    }
  }
  
  Future<void> _loadLiveNews() async {
    List<dynamic>? fetchedTimings;

    try {
      final String backendUrl = "$_apiBaseUrl/news";

      final response = await http.post(
        Uri.parse(backendUrl),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "category": _currentChannel,
          "compression": _selectedCompression, 
          "language": _selectedLanguage,  
          "speech_rate": _speechRate,
          'title': _currentTitle,
        }),
      );
   
      if (response.statusCode == 200) {
        final Map<String, dynamic> data = json.decode(utf8.decode(response.bodyBytes));

        _audioUrl = (data['audio_url'] as String).trim();
        fetchedTimings = data['timings'];
        setState(() {
          _wordTimings = List<Map<String, dynamic>>.from(fetchedTimings!);
        });
        logger.i('Fetched timings: $_wordTimings');
      } else {
        logger.e("Server error: ${response.statusCode}");
      }
    } catch (e) {
      logger.e("Can't connect. Check backend");
    }

    if (_isPlaying) {
      _speak(_audioUrl);
    }
  }

  Future<void> _speak(String url) async {
    _audioUrl = url;
    if (_audioUrl == ''){
      await _loadOrGoOffline();
      if (_audioUrl == '') return;
    } 

    final session = await AudioSession.instance;
    if (!(await session.setActive(true))) return;

    globalAudioHandler.mediaItem.add(MediaItem(
      id: _audioUrl,
      album: _currentChannel,
      title: _currentTitle,
      artist: _currentChannel,
      duration: const Duration(hours: 1),
    ));

    logger.i('Attempting to play URL: $_audioUrl');
    try {
      // Checking if user online to choose correct set
      if (_isOnline) {
        await _audioPlayer.setUrl(_audioUrl,).timeout(
          const Duration(seconds: 10),
          onTimeout: () => throw Exception("Connection to server timed out"),
        );
      } else {
        _audioPlayer.setFilePath(_audioUrl); 
      }

      await _audioPlayer.play();

      _audioHandler.updatePlaybackState(true);

      setState(() => _isPlaying = true);
      logger.i('Playing status in _speak: $_isPlaying');

    } catch (e) {
      logger.e("Error with URL $_audioUrl: $e");
    }
  }

  Future<void> _stop() async {
      await _audioPlayer.stop();
      _audioHandler.updatePlaybackState(false);
      setState(() => _isPlaying = false);
      logger.i('[HEADSET] Playing status in _stop: $_isPlaying');

  }

  Future<void> _stopVosk() async {
    logger.d('[VOSK] Forcing hard stop of Vosk SpeechService...');
    
    if (_voskSubscription != null) {
      await _voskSubscription!.cancel();
      _voskSubscription = null;
      logger.i('[VOSK] Stream subscription successfully canceled.');
    }

    if (_speechService != null) {
      try {
        await _speechService!.stop();
        logger.i('[VOSK] Native speech service stopped.');
      } catch (e) {
        logger.e('[VOSK] Error while stopping speech service: $e');
      }
    }

    setState(() => _isListening = false);

    await Future.delayed(const Duration(milliseconds: 200));
  }

  Future<void> _listen() async {
    logger.d('[VOSK] Received request to START mic. Current status: _isListening=$_isListening');

    if (_isIniatializing) {
      logger.d("[VOSK] Already initializing, skipping start request");
      return;
    }

    if (_isListening) {
      logger.d("[VOSK] Mic is already listening and service is active. Skipping.");
      return;
    }

    setState(() => _isIniatializing = true);

    try {

      if (!_isVoskReady || _recognizer == null) {
        logger.w("[VOSK] Vosk is not ready yet.");
        return;
      }

      if (_speechService == null) {
        logger.d('[VOSK] SpeechService does not exist. Creating a NEW instance...');
        _speechService = await _vosk.initSpeechService(_recognizer!);
      } else {
        logger.d('[VOSK] SpeechService ALREADY exists. Reusing it...');
      }

      if (_voskSubscription != null) {
        logger.d('[VOSK] Destroying subscription');
        await _voskSubscription!.cancel();
      }


      _voskSubscription = _speechService!.onResult().listen((jsonResult) {
        try {
          if (_selectedCommandMode == 'button') return;

          final Map<String, dynamic> parsed = json.decode(jsonResult);
          if (parsed.containsKey('text') && parsed['text'].toString().isNotEmpty) {
            String recognizedWords = parsed['text'].toString();
            logger.i("[VOSK] Final result: $recognizedWords");

            setState(() => _recognizedText = recognizedWords);
            _executeCommand(recognizedWords);
          }
        } catch (e) {
          logger.e("[VOSK] Cannot parse JSON: $e");
        }
      });

      logger.i('[VOSK] Starting audio stream...');
      await _speechService!.start(); 
      
      setState(() => _isListening = true);

      logger.i('[VOSK] Mic is successfully open and active.');

    } catch (e) {
        logger.e("[VOSK] Cannot start audio stream: $e");
        setState(() => _isListening = false);
    } finally {
        setState(() => _isIniatializing = false);
        logger.i('[VOSK] Initialization function finished.');
    }
  }

  Future<void> _switch() async {
    logger.i('Sometime there will be something');
  }

  void _executeCommand(String text) async {
    String t = text.toLowerCase().replaceAll(RegExp(r'[^\w\sа-яА-ЯіІєЄїЇґҐ]'), '').trim();

    logger.d("[PARSER] Command: '$t' | Mode: $_selectedCommandMode");

    if (_selectedCommandMode == 'button'){
      logger.d('[PARSER] In button mode, so shutting down parser');
      return;
    }
    if (_selectedCommandMode == 'ok, styslo') {
      if (t.contains("окей стисло") || t.contains("ок стисло") || t.contains("hey styslo")) {
        t = t.replaceAll(RegExp(r'(окей стисло|ок стисло|hey styslo)'), '').trim();
        logger.i("[PARSER] Wakeword found. Cleaned command: '$t'");
        if (t.isEmpty){
          logger.d('[PARSER] Empty command after wakeword.');
          if (_audioUrl != ''){
            await _speak(_audioUrl);
          } else {
            await _loadOrGoOffline();
          }
        }
      } else {
        logger.w("[PARSER] Ignored: without wakeword.");
        return;
      }
    }

    if (t.contains("пауз") || t.contains("стоп") || t.contains("зупини") || t.contains("stop")) {
      logger.d('[PARSER] Stop command recognized.');
      await _stop();
      return;
    }

    if (t.contains("читай") || t.contains("увімкни") || t.contains("запусти") || t.contains("play") || t.contains("старт")) {
       logger.d("[PARSER] Play command recognized.");
       if (_audioUrl != '') {
         await _speak(_audioUrl);
         t = t.replaceAll(RegExp(r'(читай|увімкни|запусти|play|старт)'), '').trim(); 
       }
    }

    if (!_isConfigLoaded) {
      logger.e("[PARSER] Error: Server config not loaded yet.");
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
          logger.d("[PARSER] Category matched: '$catName' for trigger '$trigger'");
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
          logger.d("[PARSER] Compression matched: '$compMode' for trigger '$trigger'");
          break compressionLoop;
        }
      }
    }

    if (nextChannel != _currentChannel || nextCompression != _selectedCompression){
      isChanged = true;
      final prefs = await SharedPreferences.getInstance();
      setState(() {
        _speechRate = prefs.getDouble('speech_rate') ?? 0.5;
        _selectedLanguage = prefs.getString('selected_language') ?? 'uk-UA';
        _currentChannel = prefs.getString('current_channel') ?? 'General';
      });
        }

    if(isChanged){
      logger.d("[PARSER] Changes detected. Applying new settings: Channel: '$nextChannel', Compression: '$nextCompression'");
      setState(() {
      _currentChannel = nextChannel;
      _selectedCompression = nextCompression;
    }); 
      await _savePreferences();
      await _loadOrGoOffline();
    } else{
      logger.d("[PARSER] No changes to apply.");
  
      if (_audioUrl != '') {
        await _speak(_audioUrl);
      } else {
        logger.w("[PARSER] No without _audioUrl.");
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
                      await _savePreferences();
                      await Future.microtask(() async {
                        try {
                        if (newMode == 'ok, styslo') {
                            logger.i("[SETTINGS] Switched to 'ok, styslo'. Ensuring mic is fresh and starting...");
                            await _listen();
                        } else {
                            logger.i("[SETTINGS] Switched to '$newMode'. Turning off Vosk completely.");
                            await _stopVosk();
                          }
                        } catch (e){
                          logger.e("[SETTINGS] Error handling command mode change: $e");
                        }
                      });
                    },
                    
                    onLanguageChanged: (newLang) async {
                      setState(() => _selectedLanguage = newLang);
                      await _savePreferences();
                    },
                    onSpeechRateChanged: (newRate) async {
                      setState(() => _speechRate = newRate);
                      await _savePreferences();
                      await _loadOrGoOffline();
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
            if(!_isOnline)
              Container(
                width: double.infinity,
                margin: const EdgeInsets.only(bottom: 16),
                padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
                decoration: BoxDecoration(
                  color: Colors.redAccent.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.redAccent),
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.offline_bolt, color: Colors.redAccent, size: 20),
                    SizedBox(width: 8),
                    Text(
                      "You're offline. Check your connection",
                      style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
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
                    "$_currentTitle ",
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
                          _wordTimings.isNotEmpty
                              ? RichText(
                                  text: TextSpan(
                                    style: const TextStyle(color: Colors.white, fontSize: 16, height: 1.6),
                                    children: _wordTimings.asMap().entries.map((entry) {
                                      int index = entry.key;
                                      String word = entry.value['Word'] ?? 'Unknown';
                                      bool isHighlighted = index == _currentlyHighlightedIndex;

                                      return TextSpan(
                                        text: "$word " ,
                                        style: isHighlighted
                                          ? const TextStyle(color: Colors.black, backgroundColor: Colors.yellowAccent)
                                          : const TextStyle(color: Colors.white)
                                      );
                                    }).toList(),
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
                                  _loadOrGoOffline();
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
                                    _speak(_audioUrl);
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