import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

void main() {
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(title: 'Real-Time Transcriber', home: MicScreen());
  }
}

class MicScreen extends StatefulWidget {
  @override
  _MicScreenState createState() => _MicScreenState();
}

class _MicScreenState extends State<MicScreen> {
  final AudioRecorder _recorder = AudioRecorder();
  bool _isRecording = false;
  String _transcription = "Press the mic to start speaking.";
  Timer? _silenceTimer;
  double _lastAmplitude = -60.0; // Initial value
  static const double SILENCE_THRESHOLD = 30.0; // 30% change threshold
  int _silenceCount = 0;
  static const int SILENCE_DURATION = 12; // Number of consecutive silent samples needed
  bool _hasDetectedSpeech = false;
  static const double SPEECH_START_THRESHOLD = 50.0; // Threshold to detect start of speech

  Future<String> _getTempFilePath() async {
    final dir = await getTemporaryDirectory();
    return p.join(dir.path, 'recorded_audio.m4a');
  }

  Future<void> _startRecording() async {
    if (await _recorder.hasPermission()) {
      final path = await _getTempFilePath();
      await _recorder.start(const RecordConfig(encoder: AudioEncoder.aacLc), path: path);
      setState(() => _isRecording = true);
      _silenceCount = 0;
      _hasDetectedSpeech = false; // Reset speech detection flag

      _recorder.onAmplitudeChanged(const Duration(milliseconds: 100)).listen((amplitude) {
        double currentAmp = amplitude.current;
        
        // Calculate percentage change
        double percentageChange = ((currentAmp - _lastAmplitude) / _lastAmplitude).abs() * 100;
        debugPrint("Change: $percentageChange%, Speech Detected: $_hasDetectedSpeech"); // Debug log

        // Detect start of speech
        if (!_hasDetectedSpeech && percentageChange > SPEECH_START_THRESHOLD) {
          _hasDetectedSpeech = true;
          debugPrint("Speech started!"); // Debug log
        }

        // Only check for silence after speech has been detected
        if (_hasDetectedSpeech) {
          if (percentageChange < SILENCE_THRESHOLD) {
            _silenceCount++;
            debugPrint("Silence count: $_silenceCount"); // Debug log
            if (_silenceCount >= SILENCE_DURATION) {
              _stopAndSendRecording();
              _silenceCount = 0;
            }
          } else {
            _silenceCount = 0;
          }
        }

        _lastAmplitude = currentAmp;
      });
    } else {
      setState(() => _transcription = "Mic permission not granted.");
    }
  }

  Future<void> _stopAndSendRecording() async {
    _silenceTimer?.cancel();
    final path = await _recorder.stop();
    setState(() => _isRecording = false);

    if (path != null && File(path).existsSync()) {
      setState(() => _transcription = "Transcribing...");
      await _uploadAudio(File(path));
    } else {
      setState(() => _transcription = "No audio recorded.");
    }
  }

  Future<void> _uploadAudio(File file) async {
    try {
      final request = http.MultipartRequest(
        'POST',
        Uri.parse('http://192.168.51.204:8000/transcribe/'), // Adjust IP if needed
      );
      request.files.add(await http.MultipartFile.fromPath('file', file.path));
      final response = await request.send();

      if (response.statusCode == 200) {
        final text = await response.stream.bytesToString();
        setState(() => _transcription = text);
      } else {
        setState(() => _transcription = "Failed: ${response.statusCode}");
      }
    } catch (e) {
      setState(() => _transcription = "Error: $e");
    }
  }

  @override
  void dispose() {
    _recorder.dispose();
    _silenceTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text("Click to Speak")),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          children: [
            GestureDetector(
              onTap: () {
                if (_isRecording) {
                  _stopAndSendRecording();
                } else {
                  _startRecording();
                }
              },
              child: CircleAvatar(
                radius: 40,
                backgroundColor: _isRecording ? Colors.red : Colors.blue,
                child: Icon(
                  _isRecording ? Icons.mic : Icons.mic_none,
                  color: Colors.white,
                  size: 40,
                ),
              ),
            ),
            const SizedBox(height: 30),
            Text(
              "Transcription:",
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            Expanded(child: SingleChildScrollView(child: Text(_transcription))),
          ],
        ),
      ),
    );
  }
}