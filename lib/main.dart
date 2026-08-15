// ====  Essential imports ==== 
import 'dart:convert';
import 'package:flutter/material.dart';

// ====  Audio imports ==== 
import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:just_audio/just_audio.dart';

// ====  Internet imports ==== 
import 'package:http/http.dart' as http;
import 'package:connectivity_plus/connectivity_plus.dart';
import 'dart:async';

// ====  Offline imports ==== 
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';

// ====  Ok, Styslo imports ==== 
import 'package:vosk_flutter/vosk_flutter.dart';

// ====  Logs import ==== 
import 'package:logger/logger.dart';

// ====  Other screens imports ==== 
import 'audio_command_handler.dart';
import 'digests_screen.dart';
import 'sources_screen.dart';
import 'settings_screen.dart';
import 'local_database.dart';


late AudioCommandHandler globalAudioHandler;
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Check if version release to turn off logger
  if (const bool.fromEnvironment('dart.vm.product')) {
    Logger.level = Level.off; 
  }

  // Initializiting AudioHandler to show notifications
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

// Player Screen 
class _PlayerScreenState extends State<PlayerScreen> {
  // ==== Screens ====
  int _currentIndex = 0; // 0 — home, 1 — digest_screen, 2 — sources_screen, 3 — settings_screen 

  // ====  Audio settings ==== 
  final AudioPlayer _audioPlayer = AudioPlayer();
  late AudioCommandHandler _audioHandler;
  String _currentTitle = 'Lorem Ipsum';
  String _selectedLanguage = "uk-UA";
  double _speechRate = 0.5;
  bool _isPlaying = false;
  String _selectedCompression = "Compressed(only main thought)";
  List<Map<String, dynamic>> _wordTimings = [];
  int _currentlyHighlightedIndex = -1;
  String _audioUrl = '';

  // ====  Categories ==== 
  String _currentChannel = "General"; 
  List<String> _dynamicCategories = ["General"]; // Holds just the names for dropdowns
  List<dynamic> _dynamicCategoriesWithSource = []; // Holds full maps with sources (offline sources)
  bool _isCategoriesLoading = true;

  // ====  Internet related ==== 
  final String _apiBaseUrl = "http://192.168.1.126:8000/api";
  Map<String, dynamic> _remoteCategories = {};
  Map<String, dynamic> _remoteCompression = {};
  bool _isConfigLoaded = false;
  StreamSubscription<List<ConnectivityResult>>? _subscription;
  bool _isOnline = false;

  // ====  Intent parser ==== 
  StreamSubscription? _voskSubscription;
  Model? _voskModel;
  Recognizer? _recognizer;
  SpeechService? _speechService;
  final TextEditingController _commandController = TextEditingController();
  final VoskFlutterPlugin _vosk = VoskFlutterPlugin.instance();
  bool _isVoskReady = false;
  bool _isListening = false;
  bool _isIniatializing = false;
  String _recognizedText = '';
  String _selectedCommandMode = 'button';
  
  // ====  Logs ==== 
  final logger = Logger(
  printer: PrettyPrinter(
    methodCount: 0,       
    errorMethodCount: 5,  
    lineLength: 80,       
    colors: true,         
  ),
);

  // Initializiting services
  @override
  void initState() {
    super.initState();
    _initVosk();  
    _initAudioService();
    _initAudioPlayer();
    _checkConnect();
  }

  void _initAudioPlayer() async {
    // Listening stream to highlight current word
    _audioPlayer.positionStream.listen((position) {
      int milliseconds = position.inMilliseconds;
      double currentSeconds = milliseconds / 1000.0; // Because Whisper returns in seconds and AudioPlayer listens in milliseconds 

      // Highlighting word with information from Whisper
      int newIndex = _wordTimings.indexWhere((timing) {
        double start = timing['Start']; 
        double end = timing['End'];

        return currentSeconds >= start && currentSeconds <= end; 
      });

      // Checking for false triggering
      if (newIndex != -1 && newIndex != _currentlyHighlightedIndex) {
        setState(() {
          _currentlyHighlightedIndex = newIndex;
        });
      }
    });
  }

  void _initVosk() async {
    logger.i("[VOSK] Initializing Vosk model...");
    // Loading vosk model from assets
    try{
      final modelPath = await ModelLoader().loadFromAssets('assets/models/voice/uk.zip');
      _voskModel = await _vosk.createModel(modelPath);
      _recognizer = await _vosk.createRecognizer(model: _voskModel!, sampleRate: 16000); // Setting listening 

      // Setting variable to check later
      setState(() => _isVoskReady = true);
      logger.i("[VOSK] Model initialized successfully.");
    } catch (e) {
      logger.d("[VOSK] Error initializing Vosk model: $e");
    }
  }

  Future<void> _initAudioService() async {
    // Handling commands from,headphones
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

  // Cleaning up after ending work
  @override
  void dispose() {
    // Headphones
    _audioHandler.onPlayTriggered = null;
    _audioHandler.onPauseTriggered = null;
    _audioHandler.onNextTriggered = null;
    _audioHandler.onPreviousTriggered = null;

    // Text
    _commandController.dispose();
    // Intent parser
    _voskSubscription?.cancel();
    _speechService?.stop();

    //Internet
    _subscription?.cancel();

    super.dispose();
  }

  

  Future<void> _fetchConfig() async {
    // Loading preferences in case offline
    await _loadPreferences();

    // If online: getting categories from server
    if (_isOnline) {
      // Sync
      try {
        // Retriving all actions from local db 
        final pendingActions = await LocalDatabase.instance.getPendingActions();
        for (var item in pendingActions) {
          final int rowId = item['id'];
          final String targetType = item['target_type'].toString();
          final String targetValue = item['target_value'].toString();

          http.Response? response;
          // Sync any offline actions to the backend first to avoid crashing
          if (targetType == 'category_del') {
            response = await http.delete(
              Uri.parse("$_apiBaseUrl/categories/${Uri.encodeComponent(targetValue)}"),
            );
          } else if (targetType == 'source_del') {
            response = await http.delete(
              Uri.parse("$_apiBaseUrl/sources/${Uri.encodeComponent(targetValue)}"),
            );
          } else if (targetType == 'category_add') {
            response = await http.post(
              Uri.parse("$_apiBaseUrl/categories"),
              headers: {"Content-Type": "application/json"},
              body: json.encode({"name": targetValue}),
            );
          } else if (targetType == 'source_add') {
            final Map<String, dynamic> srcMap = json.decode(targetValue);
            response = await http.post(
              Uri.parse("$_apiBaseUrl/sources"),
              headers: {"Content-Type": "application/json"},
              body: json.encode(srcMap),
            );
          }

          if (response != null && (response.statusCode == 200 || response.statusCode == 404)) {
            // Successfully synced actions, remove from pending audit table
            await LocalDatabase.instance.clearPendingActions(rowId);
          }
        }

        // Getting sources from server
        final response = await http.get(Uri.parse("$_apiBaseUrl/sources"));
        if (response.statusCode == 200) {
          final data = json.decode(utf8.decode(response.bodyBytes));

          List<dynamic> categoriesList = [];
          Map<String, dynamic> remoteCategoriesMap = {};
          Map<String, dynamic> remoteCompressionMap = {};

          // Download data to offline use in source screen
          // Handle if root response is a List (like categories with sources array)
          if (data is List) {
            categoriesList = data.map((cat) {
              if (cat is Map) {
                final catName = cat["category_name"]?.toString() ?? "General";
                final rawSources = cat["sources"] ?? [];
                List parsedSources = [];
                if (rawSources is List) {
                  parsedSources = rawSources.map((s) {
                    if (s is Map) {
                      return {
                        "id": s["id"],
                        "name": s["name"] ?? s["title"] ?? "Unknown",
                        "url": s["url"] ?? s["url_or_credentials"] ?? "",
                      };
                    }
                    return {"name": s.toString(), "url": ""};
                  }).toList();
                }
                return {
                  "category_name": catName,
                  "sources": parsedSources,
                };
              }
              return {"category_name": cat.toString(), "sources": []};
            }).toList();
          } else if (data is Map) {
            // If root response is a Map containing a "categories" key
            final rawCategories = data["categories"] ?? [];
            if (rawCategories is Map) {
              categoriesList = rawCategories.entries.map((entry) {
                final val = entry.value;
                List parsedSources = [];
                if (val is List) {
                  parsedSources = val.map((s) {
                    if (s is Map) return s;
                    return {"name": s.toString(), "url": ""};
                  }).toList();
                }
                return {
                  "category_name": entry.key.toString(),
                  "sources": parsedSources,
                };
              }).toList();
            } else if (rawCategories is List) {
              categoriesList = rawCategories.map((cat) {
                if (cat is Map) {
                  return {
                    "category_name": cat["category_name"]?.toString() ?? "General",
                    "sources": cat["sources"] is List ? cat["sources"] : [],
                  };
                }
                return {"category_name": cat.toString(), "sources": []};
              }).toList();
            }

            if (data["categories"] is Map<String, dynamic>) {
              remoteCategoriesMap = data["categories"];
            }
            if (data["compression"] is Map<String, dynamic>) {
              remoteCompressionMap = data["compression"];
            }
          }

          setState(() {
            _remoteCategories = remoteCategoriesMap;
            _remoteCompression = remoteCompressionMap;
            _dynamicCategoriesWithSource = categoriesList;

            // Extract names safely for the dropdown UI
            _dynamicCategories = categoriesList.map((cat) => cat["category_name"].toString()).toList();
            
            if (_dynamicCategories.isNotEmpty && !_dynamicCategories.contains(_currentChannel)) {
              _currentChannel = _dynamicCategories.first;
            }
            _isCategoriesLoading = false;
            _isConfigLoaded = true;
          });

          // Saving categories and sources into local db for offline use
          await LocalDatabase.instance.saveCategoriesAndSources(_dynamicCategoriesWithSource);
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
      } else {
        _currentChannel = 'General';
      }
      _isCategoriesLoading = false;
      _isConfigLoaded = localCategories.isNotEmpty;
    });
  }

  // Saving audio variables for offline
  Future<void> _savePreferences() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('speech_rate', _speechRate);
    await prefs.setString('selected_language', _selectedLanguage);
    await prefs.setString('current_channel', _currentChannel);
  }

  // Loading audio variables for offline
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
            audioPath: localFile.path, // Saving local path instead of link
            timingsJson: jsonEncode(timings),
          );

          logger.i("Successfully cached category '$categoryName'.");
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

  // Online mode: Loading from server
  Future<void> _loadLiveNews() async {
    // Timings to highlight words
    List<dynamic>? fetchedTimings;

    try {
      final String backendUrl = "$_apiBaseUrl/news";

      // Sending request to get_news
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

      // If successful, return audio URL and timings
      if (response.statusCode == 200) {
        final Map<String, dynamic> data = json.decode(utf8.decode(response.bodyBytes));

        _audioUrl = (data['audio_url'] as String).trim();
        fetchedTimings = data['timings'];
        setState(() {
          _wordTimings = List<Map<String, dynamic>>.from(fetchedTimings!);
        });
        logger.d('Fetched timings: $_wordTimings');
      } else {
        logger.e("Server error: ${response.statusCode}");
      }
    } catch (e) {
      logger.e("Can't connect. Check backend");
    }
    // Start playing at once if pressed button
    if (_isPlaying) {
      _speak(_audioUrl);
    }
  }

  // Function to play audio 
  Future<void> _speak(String urlOrPath) async {
    if (urlOrPath.isEmpty) {
    await _loadOrGoOffline(); // Using universal loader
    if (_audioUrl.isEmpty) return;
    urlOrPath = _audioUrl;
  }

    // Activating audio session to show notification and handle headphones
    final session = await AudioSession.instance;
    if (!(await session.setActive(true))) return;

    globalAudioHandler.mediaItem.add(MediaItem(
      id: urlOrPath,
      album: _currentChannel,
      title: _currentTitle,
      artist: _currentChannel,
      duration: const Duration(hours: 1),
    ));

   try {
    // Check if local then use setFilePath
    if (urlOrPath.startsWith('/') || urlOrPath.contains('application_documents')) {
      logger.i('Attempting to play LOCAL file: $urlOrPath');
      await _audioPlayer.setFilePath(urlOrPath);
    } else {
      logger.i('Attempting to play NETWORK URL: $urlOrPath');
      await _audioPlayer.setUrl(urlOrPath).timeout(
        const Duration(seconds: 10), // In case of network issues
        onTimeout: () => throw Exception("Connection timed out"),
      );
    }

    await _audioPlayer.play();
    _audioHandler.updatePlaybackState(true);
    setState(() => _isPlaying = true);

  } catch (e) {
    logger.e("Error playing audio source ($urlOrPath): $e");
  }
}
  // Function to stop audio
  Future<void> _stop() async {
      await _audioPlayer.stop();
      _audioHandler.updatePlaybackState(false);
      setState(() => _isPlaying = false);
      logger.i('[HEADSET] Playing status in _stop: $_isPlaying');

  }

  // Function to listen said in "Ok, Styslo" mode.
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
      // Checking if listener and recognizer are ready
      if (!_isVoskReady || _recognizer == null) {
        logger.w("[VOSK] Vosk is not ready yet.");
        return;
      }

      if (_speechService == null) {
        logger.d('[VOSK] SpeechService does not exist. Creating a NEW instance...');
        // If speech service is not initialized, creating a new one
        _speechService = await _vosk.initSpeechService(_recognizer!);
      } else {
        logger.d('[VOSK] SpeechService ALREADY exists. Reusing it...');
      }

      if (_voskSubscription != null) {
        logger.d('[VOSK] Destroying subscription');
        await _voskSubscription!.cancel(); // If exists, canceling previous subscription to prevent multiple listeners
      }

      // Creating a new subsctiption to listen for results
      _voskSubscription = _speechService!.onResult().listen((jsonResult) {
        try {
          // If in button mode, return to prevent leaking memory
          if (_selectedCommandMode == 'button') return;

          // Parsing JSON result from Vosk
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

      // Starting the speech service to listen for commands
      logger.i('[VOSK] Starting audio stream...');
      await _speechService!.start(); 
      
      setState(() => _isListening = true);

      logger.i('[VOSK] Mic is successfully open and active.');

    } catch (e) {
        logger.e("[VOSK] Cannot start audio stream: $e");
        setState(() => _isListening = false);
    } finally {
        // After finishing initialization, set the flag to false to allow future attempts
        setState(() => _isIniatializing = false);
        logger.i('[VOSK] Initialization function finished.');
    }
  }

  // Function to stop listening
  Future<void> _stopVosk() async {
    logger.d('[VOSK] Forcing hard stop of Vosk SpeechService...');
    
    // Canceling subsciption if it exists
    if (_voskSubscription != null) {
      await _voskSubscription!.cancel();
      _voskSubscription = null;
      logger.i('[VOSK] Stream subscription successfully canceled.');
    }

    // Stopping speech service if it exists
    if (_speechService != null) {
      try {
        await _speechService!.stop();
        logger.i('[VOSK] Native speech service stopped.');
      } catch (e) {
        logger.e('[VOSK] Error while stopping speech service: $e');
      }
    }

    setState(() => _isListening = false);

    // Making sure the stop correctly finished (hardware might need sometime to process)
    await Future.delayed(const Duration(milliseconds: 200));
  }

  // Function to process skipping and coming back to previous audio
  Future<void> _switch() async {
    logger.i('Sometime there will be something');
  }

  // Voice command parser. It will check for wakeword, then check for category and compression triggers, then apply changes if needed
  void _executeCommand(String text) async {
    // Clean up text after removing punctuation 
    String t = text.toLowerCase().replaceAll(RegExp(r'[^\w\sа-яА-ЯіІєЄїЇґҐ]'), '').trim();

    // Logging the command and current mode
    logger.d("[PARSER] Command: '$t' | Mode: $_selectedCommandMode");

    // Shutting down parser if in button mode
    if (_selectedCommandMode == 'button'){
      logger.d('[PARSER] In button mode, so shutting down parser');
      return;
    }

    // Cheking for wakeword if in "Ok, Styslo" mode
    if (_selectedCommandMode == 'ok, styslo') {
      if (t.contains("окей стисло") || t.contains("ок стисло") || t.contains("hey styslo")) {
        t = t.replaceAll(RegExp(r'(окей стисло|ок стисло|hey styslo)'), '').trim(); // Cleaning up command after wakeword 
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
        // Failsafe: if wakeword is not found, ignore command
        logger.w("[PARSER] Ignored: without wakeword.");
        return;
      }
    }

    // Checking for stop command  
    if (t.contains("пауз") || t.contains("стоп") || t.contains("зупини") || t.contains("stop")) {
      logger.d('[PARSER] Stop command recognized.');
      await _stop();
      return;
    }

    // Checking for play command 
    if (t.contains("читай") || t.contains("увімкни") || t.contains("запусти") || t.contains("play") || t.contains("старт")) {
       logger.d("[PARSER] Play command recognized.");
       if (_audioUrl != '') {
         await _speak(_audioUrl);
         t = t.replaceAll(RegExp(r'(читай|увімкни|запусти|play|старт)'), '').trim(); 
       }
    }

    // Failsafe: before processsing next segment
    if (!_isConfigLoaded) {
      logger.e("[PARSER] Error: Server config not loaded yet.");
      return;
    } 

    // Parser variables
    String nextChannel = _currentChannel;
    String nextCompression = _selectedCompression;
    bool isChanged = false;

    // Looping through all categories and their triggers(server side)
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

    // Looping through all compression mode and their triggers(server side)
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

    // Checking if any changes happened and applying them if needed
    if (nextChannel != _currentChannel || nextCompression != _selectedCompression){
      isChanged = true;
      // Saving new setting for offline mode
      final prefs = await SharedPreferences.getInstance();
      setState(() {
        _speechRate = prefs.getDouble('speech_rate') ?? 0.5;
        _selectedLanguage = prefs.getString('selected_language') ?? 'uk-UA';
        _currentChannel = prefs.getString('current_channel') ?? 'General';
      });
        }

    // Logging and applying changes if there are
    if(isChanged){
      logger.d("[PARSER] Changes detected. Applying new settings: Channel: '$nextChannel', Compression: '$nextCompression'");
      setState(() {
      _currentChannel = nextChannel;
      _selectedCompression = nextCompression;

    });
      // Saving for offline and using universal loader to play audio   
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

  // UI
  Widget _buildHomeTab() {
    return SingleChildScrollView(
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
                  Text("You're offline. Check your connection", style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
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
                  style: const TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.bold, letterSpacing: 1.5),
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
                                    text: "$word ",
                                    style: isHighlighted ? const TextStyle(color: Colors.black, backgroundColor: Colors.yellowAccent) : const TextStyle(color: Colors.white)
                                  );
                                }).toList(),
                              ),
                            )
                          : const Text(
                              "Lorem ipsum dolor sit amet, consectetur adipiscing elit...",
                              style: TextStyle(color: Colors.white70, fontSize: 15),
                            ),
                      const SizedBox(height: 20),
                      Column(
                        children: [
                          const SizedBox(height: 15),
                          _isCategoriesLoading
                              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                              : DropdownButton<String>(
                                  value: _currentChannel,
                                  dropdownColor: Colors.black,
                                  style: const TextStyle(color: Colors.white, fontSize: 16),
                                  icon: const Icon(Icons.arrow_drop_down, color: Colors.blueAccent),
                                  items: _dynamicCategories.map<DropdownMenuItem<String>>((String value) {
                                    return DropdownMenuItem<String>(value: value, child: Text(value));
                                  }).toList(),
                                  onChanged: (String? newValue) {
                                    if (newValue != null) {
                                      setState(() => _currentChannel = newValue);
                                      _loadOrGoOffline();
                                    }
                                  },
                                ),
                          IconButton(
                            icon: const Icon(Icons.download, color: Colors.blueAccent),
                            tooltip: "Download for offline",
                            onPressed: () async {
                              bool success = true;
                              try {
                                await downloadCategoryOffline(_currentChannel);
                              } catch(e) {
                                setState(() => success = false);
                              }

                              if (!mounted) return;

                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text(success ? "Category '$_currentChannel' downloaded!" : "Failed to download '$_currentChannel'.")),
                              );
                              
                            },
                          ),
                          const SizedBox(height: 20),
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
                                onPressed: () => logger.d("[AUDIO HANDLER] Skip backward pressed"),
                              ),
                              const SizedBox(width: 24),
                              GestureDetector(
                                onTap: () {
                                  setState(() => _isPlaying = !_isPlaying);
                                  if (_isPlaying) {
                                    _speak(_audioUrl);
                                  } else {
                                    _stop();
                                  }
                                },
                                child: CircleAvatar(
                                  radius: 45,
                                  backgroundColor: _isPlaying ? Colors.red : Colors.blueAccent,
                                  child: Icon(_isPlaying ? Icons.pause : Icons.play_arrow, size: 40, color: Colors.white),
                                ),
                              ),
                              const SizedBox(width: 20),
                              IconButton(
                                iconSize: 36,
                                icon: const Icon(Icons.skip_next, color: Colors.blueAccent),
                                onPressed: () => logger.d("[AUDIO HANDLER] Skip forward pressed"),
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
    );
  }

  @override
  Widget build(BuildContext context) {
    // Defining corresponding bodies based on active bottom navigation index
    final List<Widget> pages = [
      _buildHomeTab(),
      DigestsScreen(
        initialLanguage: _selectedLanguage,
        initialSpeechRate: _speechRate,
        initialCompression: _selectedCompression,

        onLanguageChanged: (newLang) async {
          setState(() => _selectedLanguage = newLang);
          await _savePreferences();
          await _loadOrGoOffline();
        },
        onSpeechRateChanged: (newRate) async {
          setState(() => _speechRate = newRate);
          await _savePreferences();
          await _loadOrGoOffline();
        },
        onCompressionChanged: (newCompression) async {
          setState(() => _selectedCompression = newCompression);
          await _savePreferences();
          await _loadOrGoOffline();
        },
        onGenerateDigest: () async {
          await _loadLiveNews();
        },
        onDownloadDigest: () async {
          await downloadCategoryOffline(_currentChannel);
        },
      ),
     
      SourcesScreen(initialStatus: _isOnline),

      SettingsScreen(
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
    ];

    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        backgroundColor: Colors.black,
      ),
      body: pages[_currentIndex],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        backgroundColor: Colors.black,
        selectedItemColor: Colors.blueAccent,
        unselectedItemColor: Colors.grey,
        type: BottomNavigationBarType.fixed,
        onTap: (index) {
          setState(() {
            _currentIndex = index;
          });
          // Refresh configuration data if switching back to Home or Sources
          if (index == 0 || index == 2) {
            _fetchConfig();
          }
        },
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.home),
            label: 'Home',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.auto_awesome),
            label: 'Digest',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.list_alt),
            label: 'Sources',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.settings),
            label: 'Settings',
          ),
        ],
      ),
    );
  }
}