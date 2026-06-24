import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

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
  bool _isListening = false;
  String _recognizedText = "Press me";

  String _currentChannel = "General";
  String _compressionLevel = "Normal";
  bool _isPlaying = false;

  @override
  void initState() {
    super.initState();
    _speech = stt.SpeechToText();
  }

 void _listen() async {
    if (!_isListening) {
      bool available = await _speech.initialize(
        onStatus: (val) => print('Статус: $val'),
        onError: (val) => print('Помилка: $val'),
      );
      if (available) {
        setState(() => _isListening = true);
        _speech.listen(
          onResult: (val) => setState(() {
            _recognizedText = val.recognizedWords;
            if (val.finalResult) {
              _isListening = false;
              _executeCommand(_recognizedText); // Передаємо текст на парсинг
            }
          }),
        );
      }
    } else {
      setState(() => _isListening = false);
      _speech.stop();
    }
  }

  // Наш локальний модуль команд (Intent Parser)
  void _executeCommand(String text) {
    String t = text.toLowerCase();

    // 1. Керування плеєром
    if (t.contains("пауз") || t.contains("стоп") || t.contains("зупини")) {
      setState(() => _isPlaying = false);
      return;
    }
    if (t.contains("play") || t.contains("вруби") || t.contains("увімкни") || t.contains("слухати")) {
      setState(() => _isPlaying = true);
    }

    // 2. Вибір каналу
    if (t.contains("спорт") || t.contains("футбол")) {
      setState(() => _currentChannel = "Sport ⚽");
    } else if (t.contains("техно") || t.contains("айті") || t.contains("гаджет")) {
      setState(() => _currentChannel = "Tecnologies 💻");
    } else if (t.contains("політик") || t.contains("новини")) {
      setState(() => _currentChannel = "Politics 🏛️");
    }

    // 3. Рівень стиснення
    if (t.contains("коротко") || t.contains("стисло") || t.contains("головне")) {
      setState(() => _compressionLevel = "Compressed(only main thought)");
    } else if (t.contains("детальн") || t.contains("повністю")) {
      setState(() => _compressionLevel = "Detailed");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Styslo'),
        centerTitle: true,
        backgroundColor: Colors.black,
      ),
      body: Padding(
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
                  Text(_isPlaying ? "▶️ Playing" : "⏸️ Pause", 
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.greenAccent)),
                  const SizedBox(height: 15),
                  Text("Канал: $_currentChannel", style: const TextStyle(fontSize: 22)),
                  const SizedBox(height: 10),
                  Text("Режим: $_compressionLevel", style: const TextStyle(fontSize: 16, color: Colors.white70)),
                ],
              ),
            ),
            const SizedBox(height: 40),
            

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