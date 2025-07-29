import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:audioplayers/audioplayers.dart';
import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:string_similarity/string_similarity.dart';
  

void main() => runApp(MaterialApp(home: MicAndTextApp()));

class MicAndTextApp extends StatefulWidget {
  @override
  State<MicAndTextApp> createState() => _MicAndTextAppState();
}

/// Compares character-level similarity between input and target.
/// Returns a value between 0.0 (no match) and 1.0 (perfect match).
/// Optional threshold for match classification.
CharacterSimilarityResult compareCharSimilarity(String input, String target, {double threshold = 0.85}) {
  final cleanInput = input.toLowerCase().replaceAll(RegExp(r'[^\wäöüß]'), '').trim();
  final cleanTarget = target.toLowerCase().replaceAll(RegExp(r'[^\wäöüß]'), '').trim();

  final similarity = StringSimilarity.compareTwoStrings(cleanInput, cleanTarget);
  final isSimilar = similarity >= threshold;

  return CharacterSimilarityResult(similarity: similarity, isSimilar: isSimilar);
}

class CharacterSimilarityResult {
  final double similarity;
  final bool isSimilar;

  CharacterSimilarityResult({required this.similarity, required this.isSimilar});
}

class _MicAndTextAppState extends State<MicAndTextApp>
    with SingleTickerProviderStateMixin {
  late stt.SpeechToText _speech;
  late AudioPlayer _audioPlayer;

  bool _hasPermission = false;
  bool _quizStarted = false;
  bool _micVisible = false;
  bool _micOn = false;
  bool _isTextEntryActive = false;

  int _currentRound = 0;
  final int maxRounds = 3;

  String _recognizedText = '';
  String _inputText = '';
  String _currentSpeech = '';
  String _itemDe = '';

  int _wordCount = 0;
  int _alphabetCount = 0;

  late AnimationController _controller;
  late Animation<Alignment> _animation;

  final List<String> _audioFiles = [
    '2R6KVMP1.mp3', //radio
    '2T9JK5W8.mp3', //tisch
    '6S8QLZC1.mp3', //salz
  ];

  final List<String> _jsonFiles = [
    '2R6KVMP1.json',
    '2T9JK5W8.json',
    '6S8QLZC1.json',
  ];

  @override
  void initState() {
    super.initState();
    _speech = stt.SpeechToText();
    _audioPlayer = AudioPlayer();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 18),
    );

    _animation = Tween<Alignment>(
      begin: Alignment(-1.0, 0.9),
      end: Alignment(1.0, 0.9),
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.linear));

    _requestMicPermission();
  }

  Future<void> _loadData(String filename) async {
    final jsonString = await rootBundle.loadString('assets/audio/$filename');
    final Map<String, dynamic> jsonMap = json.decode(jsonString);

    _itemDe = jsonMap['item_de'];
    print('item_de: $_itemDe');

    final String rawText = jsonMap['text_de'] ?? '';

    final String cleaned = rawText
        .replaceAll(RegExp(r'[„“.,…]'), '')
        .replaceAll(RegExp(r'\.\.'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    final List<String> words = cleaned.split(' ');
    final List<String> filteredWords =
        words.where((w) => w.trim().isNotEmpty).toList();

    final int alphabetCount =
        cleaned.replaceAll(RegExp(r'[^A-Za-zÄÖÜäöüß]'), '').length;

    print('Raw text: $rawText');
    print('Cleaned: $cleaned');
    print('Word count: ${filteredWords.length}');
    print('Alphabet count: $alphabetCount');

    setState(() {
      _wordCount = filteredWords.length;
      _alphabetCount = _wordCount;
    });
  }

  Future<void> _requestMicPermission() async {
    final available = await _speech.initialize(
      onStatus: (status) => print("STATUS: $status"),
      onError: (error) => print("ERROR: ${error.errorMsg}"),
    );

    setState(() => _hasPermission = available);
  }

  Future<void> _startNextRound() async {
    if (_currentRound >= maxRounds) {
      setState(() {
        _recognizedText += '\n\n✅ Finished all $maxRounds rounds.';
        _micVisible = false;
        _isTextEntryActive = false;
      });
      return;
    }

    await _loadData(_jsonFiles[_currentRound]);

    final int N = _alphabetCount;
    final int firstWindow = 3*_wordCount;
    final int secondWindow = 3*_wordCount;
    final int audioWindow = 2*_wordCount;

    print('firstWindow: $firstWindow, secondWindow: $secondWindow, audioWindow: $audioWindow');

    setState(() {
      _recognizedText += '\n\n🎙 Round ${_currentRound + 1}';
      _micVisible = true;
      _micOn = true;
      _isTextEntryActive = false;
      _currentSpeech = '';
    });

    _controller.duration = Duration(seconds: firstWindow + audioWindow + secondWindow);
    _controller.reset();
    _controller.forward();

    String firstWindowSpeech = '';
    _speech.listen(
      localeId: 'de_DE',
      listenFor: Duration(seconds: firstWindow),
      onResult: (res) {
        setState(() {
          firstWindowSpeech = res.recognizedWords.trim().toLowerCase();
          _currentSpeech = firstWindowSpeech;
          print('firstWindowSpeech: $firstWindowSpeech');
          print('Recognized: $firstWindowSpeech');
          _appendLiveSpeech();
        });
      },
    );

    await Future.delayed(Duration(seconds: firstWindow));
    await _speech.stop();

    setState(() => _micOn = false);
    _appendStatus('🔇 Paused — preparing audio...');
    await Future.delayed(Duration(milliseconds: 500));

    String audioFile = _audioFiles[_currentRound];
    await _audioPlayer.play(AssetSource('audio/$audioFile'));
    await Future.delayed(Duration(seconds: audioWindow));
    await _audioPlayer.stop();

    print('firstWindowSpeech: $firstWindowSpeech');
    print('_itemDe: $_itemDe');

    var threshold = 0.5;
    var result = compareCharSimilarity(firstWindowSpeech, _itemDe, threshold: threshold);

    print('Similarity: ${result.similarity.toStringAsFixed(2)}');  // e.g., 0.67
    print('Is similar: ${result.isSimilar}');

    if (firstWindowSpeech.toLowerCase() == _itemDe.toLowerCase()) {
    //if (result > threshold){

      _appendStatus('✅ Match! Skipping second mic...');
      _advanceRound();
    } else {
      _appendStatus('❌ No match — second mic...');
      await Future.delayed(Duration(milliseconds: 500));

      bool reinitialized = await _speech.initialize(
        onStatus: (status) => print("STATUS: $status"),
        onError: (error) => print("ERROR: ${error.errorMsg}"),
      );

      if (reinitialized) {
        setState(() => _micOn = true);
        _speech.listen(
          localeId: 'de_DE',
          listenFor: Duration(seconds: secondWindow),
          onResult: (res) {
            setState(() {
              _currentSpeech = res.recognizedWords;
              _appendLiveSpeech();
            });
          },
        );
        await Future.delayed(Duration(seconds: secondWindow));
        await _speech.stop();
      }

      setState(() {
        _micVisible = false;
        _isTextEntryActive = true;
      });
    }
  }

  void _advanceRound() {
    setState(() {
      _currentRound++;
      _micVisible = false;
      _isTextEntryActive = false;
    });
    Future.delayed(const Duration(seconds: 2), _startNextRound);
  }

  void _appendLiveSpeech() {
    _recognizedText = _recognizedText.replaceAll(
      RegExp(r'\n🗣 Recognized:.*'),
      '',
    );
    _recognizedText += '\n🗣 Recognized: $_currentSpeech';
  }

  void _appendStatus(String status) {
    _recognizedText += '\n$status';
  }

  void _submitTextInput() {
    setState(() {
      _recognizedText += '\n✍️ You typed: $_inputText';
      _inputText = '';
      _isTextEntryActive = false;
      _currentRound++;
    });
    Future.delayed(const Duration(seconds: 2), _startNextRound);
  }

  @override
  void dispose() {
    _controller.dispose();
    _speech.stop();
    _audioPlayer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: !_hasPermission
          ? Center(
              child: Text(
                'Waiting for microphone permission...',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
            )
          : !_quizStarted
              ? Center(
                  child: ElevatedButton(
                    onPressed: () {
                      setState(() {
                        _quizStarted = true;
                      });
                      _startNextRound();
                    },
                    child: Text(
                      "Start Quiz",
                      style: TextStyle(fontSize: 20),
                    ),
                  ),
                )
              : Stack(children: [
                  Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: Center(
                      child: SingleChildScrollView(
                        child: Text(
                          _recognizedText,
                          style: TextStyle(fontSize: 18),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                  ),
                  if (_micVisible)
                    AnimatedBuilder(
                      animation: _animation,
                      builder: (context, child) {
                        return Align(
                          alignment: _animation.value,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                _micOn ? Icons.mic : Icons.volume_up,
                                size: 40,
                                color: _micOn ? Colors.red : Colors.blue,
                              ),
                              Text(
                                _micOn ? "Mic ON" : "Playing",
                                style: TextStyle(
                                  color: _micOn ? Colors.red : Colors.blue,
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  if (_isTextEntryActive)
                    Align(
                      alignment: Alignment.bottomCenter,
                      child: Padding(
                        padding: const EdgeInsets.all(20.0),
                        child: Row(
                          children: [
                            Expanded(
                              child: TextField(
                                onChanged: (val) => _inputText = val,
                                decoration: InputDecoration(
                                  hintText: "Type something...",
                                  border: OutlineInputBorder(),
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            ElevatedButton(
                              onPressed: _submitTextInput,
                              child: Text("Submit"),
                            ),
                          ],
                        ),
                      ),
                    ),
                ]),
    );
  }
}