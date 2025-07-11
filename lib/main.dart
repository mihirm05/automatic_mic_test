import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:audioplayers/audioplayers.dart';

void main() => runApp(MaterialApp(home: MicAndTextApp()));

class MicAndTextApp extends StatefulWidget {
  @override
  State<MicAndTextApp> createState() => _MicAndTextAppState();
}

class _MicAndTextAppState extends State<MicAndTextApp>
    with SingleTickerProviderStateMixin {
  late stt.SpeechToText _speech;
  late AudioPlayer _audioPlayer;

  bool _hasPermission = false;
  bool _isTextEntryActive = false;
  bool _micVisible = false;
  bool _micOn = false;

  int _currentRound = 0;
  final int maxRounds = 3;

  String _recognizedText = '';
  String _inputText = '';
  String _currentSpeech = '';

  late AnimationController _controller;
  late Animation<Alignment> _animation;

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

  Future<void> _requestMicPermission() async {
    final available = await _speech.initialize(
      onStatus: (status) => print("STATUS: $status"),
      onError: (error) => print("ERROR: ${error.errorMsg}"),
    );

    setState(() => _hasPermission = available);
    if (available) _startNextRound();
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

    setState(() {
      _recognizedText += '\n\n🎙 Round ${_currentRound + 1}';
      _micVisible = true;
      _micOn = true;
      _isTextEntryActive = false;
      _currentSpeech = '';
    });

    _controller.reset();
    _controller.forward();

    // 1️⃣ First 6s recording
    _speech.listen(
      localeId: 'de_DE',
      listenFor: const Duration(seconds: 6),
      onResult: (res) {
        setState(() {
          _currentSpeech = res.recognizedWords;
          _appendLiveSpeech();
        });
      },
    );
    await Future.delayed(const Duration(seconds: 6));
    await _speech.stop();
  setState(() => _micOn = false);
  _appendStatus('🔇 Paused — preparing audio...');

  // Small delay to release mic before audio playback
  await Future.delayed(Duration(milliseconds: 300));

  
  try {
    print('try playing audio');
    await _audioPlayer.play(UrlSource('assets/audio/2R6KVMP1.mp3'));
  } catch (e) {

    _appendStatus('❌ Audio error: $e');
}
    _appendStatus('🔊 Playing audio...');

    await Future.delayed(const Duration(seconds: 6));
    await _audioPlayer.stop();

    // 3️⃣ Final 6s recording
    setState(() => _micOn = true);
    _speech.listen(
      localeId: 'de_DE',
      listenFor: const Duration(seconds: 6),
      onResult: (res) {
        setState(() {
          _currentSpeech = res.recognizedWords;
          _appendLiveSpeech();
        });
      },
    );
    await Future.delayed(const Duration(seconds: 6));
    await _speech.stop();

    // Switch to typing
    setState(() { 
      _micVisible = false;
      _isTextEntryActive = true;
    });
  }

  void _appendLiveSpeech() {
    // Replace previous partial result
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
