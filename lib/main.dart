import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

void main() => runApp(MaterialApp(home: MicAndTextApp()));

class MicAndTextApp extends StatefulWidget {
  @override
  State<MicAndTextApp> createState() => _MicAndTextAppState();
}

class _MicAndTextAppState extends State<MicAndTextApp>
    with SingleTickerProviderStateMixin {
  late stt.SpeechToText _speech;
  bool _hasPermission = false;
  bool _isListening = false;
  bool _isTextEntryActive = false;
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

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 10),
    );

    _animation = Tween<Alignment>(
      begin: Alignment(-1.0, 0.9),
      end: Alignment(1.0, 0.9),
    ).animate(_controller);

    _requestMicPermission();
  }

  Future<void> _requestMicPermission() async {
    final available = await _speech.initialize(
      onStatus: (status) => print("STATUS: $status"),
      onError: (error) => print("ERROR: ${error.errorMsg}"),
    );

    setState(() {
      _hasPermission = available;
    });

    if (available) {
      _startNextRound();
    }
  }

  Future<void> _startNextRound() async {
  if (_currentRound >= maxRounds) {
    setState(() {
      _recognizedText += '\n\n✅ Finished all 3 rounds.';
      _isListening = false;
      _isTextEntryActive = false;
    });
    return;
  }

  setState(() {
    _isListening = true;
    _isTextEntryActive = false;
    _currentSpeech = '';
    _recognizedText += '\n\n🎙 Round ${_currentRound + 1} - Listening...';
  });

  _controller.reset();
  _controller.forward();

  _speech.listen(
    localeId: 'de_DE',
    listenFor: Duration(seconds: 10),
    onResult: (result) {
      setState(() {
        _currentSpeech = result.recognizedWords;

        // Update live recognized text, replacing previous partial update
        _recognizedText = _recognizedText.replaceAll(RegExp(r'\n🗣 Recognized:.*'), '');
        _recognizedText += '\n🗣 Recognized: $_currentSpeech';
      });
    },
  );

  await Future.delayed(Duration(seconds: 10));
  await _speech.stop();

  setState(() {
    _isListening = false;
    _isTextEntryActive = true;
  });

  _currentRound++;
}


  void _submitTextInput() {
    setState(() {
      _recognizedText += '\n✍️ You typed: $_inputText';
      _inputText = '';
      _isTextEntryActive = false;
    });

    Future.delayed(Duration(seconds: 2), _startNextRound);
  }

  @override
  void dispose() {
    _controller.dispose();
    _speech.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: !_hasPermission
          ? Center(
              child: Text(
                'Waiting for microphone permission...',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
            )
          : Stack(
              children: [
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
                if (_isListening)
                  AnimatedBuilder(
                    animation: _animation,
                    builder: (context, child) {
                      return Align(
                        alignment: _animation.value,
                        child: Icon(Icons.mic, size: 40, color: Colors.red),
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
              ],
            ),
    );
  }
}
