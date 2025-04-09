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

  Future<String> _getTempFilePath() async {
    final dir = await getTemporaryDirectory();
    return p.join(dir.path, 'recorded_audio.m4a');
  }

Future<void> _startRecording() async {
  if (await _recorder.hasPermission()) {
    final path = await _getTempFilePath();
    await _recorder.start(const RecordConfig(encoder: AudioEncoder.aacLc), path: path);
    setState(() => _isRecording = true);

    // Monitor audio levels for silence detection
    _recorder.onAmplitudeChanged(const Duration(milliseconds: 100)).listen((amplitude) {
      debugPrint("Amplitude: ${amplitude.current}"); // Debug log to check amplitude values

      if (amplitude.current <= 0.1) { // Lower threshold for silence
        // If silence is detected, start a timer
        _silenceTimer?.cancel();
        _silenceTimer = Timer(const Duration(milliseconds: 700), () {
          _stopAndSendRecording();
        });
      } else {
        // Reset the timer if sound is detected
        _silenceTimer?.cancel();
      }
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