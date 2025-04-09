import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter/services.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized(); // Add this line
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
  double _lastAmplitude = -25.0; // Initial value
  static const double SILENCE_THRESHOLD = 3.0; // Small changes indicate silence
  int _silenceCount = 0;
  static const int INITIAL_SILENCE_DURATION = 100;  // Before speech detection
  static const int AFTER_SPEECH_SILENCE_DURATION = 10;  // After speech detection
  int _silenceDuration = INITIAL_SILENCE_DURATION;  // Dynamic silence duration
  bool _hasDetectedSpeech = false;
  static const double SPEECH_START_THRESHOLD = 5.0; // Amplitude change to detect speech
  static const double MIN_AMPLITUDE = -28.0; // Minimum amplitude threshold

  Position? _currentPosition;
  String _country = "Unknown";
  String _locationStatus = "Location not determined";

  @override
  void initState() {
    super.initState();
    // Request location permission and get location immediately when app starts
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeLocation();
    });
  }

  Future<void> _initializeLocation() async {
    LocationPermission permission = await Geolocator.checkPermission();
    
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        setState(() => _locationStatus = 'Location permissions are denied');
        return;
      }
    }
    
    if (permission == LocationPermission.deniedForever) {
      setState(() => _locationStatus = 'Location permissions are permanently denied');
      return;
    }

    // Get location after permissions are granted
    await _getCurrentLocation();
  }

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
      _hasDetectedSpeech = false;
      _silenceDuration = INITIAL_SILENCE_DURATION;

      _recorder.onAmplitudeChanged(const Duration(milliseconds: 100)).listen((amplitude) {
        double currentAmp = amplitude.current;
        double amplitudeChange = (currentAmp - _lastAmplitude).abs();

        // Skip if amplitude change is infinite or amplitude is too low
        if (amplitudeChange.isInfinite || currentAmp < MIN_AMPLITUDE) {
          debugPrint("Skipping: ${amplitudeChange.isInfinite ? 'Infinite change' : 'Too low amplitude'}"); 
          _lastAmplitude = currentAmp;
          return;
        }

        debugPrint("Current: $currentAmp, Change: $amplitudeChange, Required silence: $_silenceDuration");

        // Wait for a significant amplitude change to start monitoring
        if (!_hasDetectedSpeech) {
          if (amplitudeChange > SPEECH_START_THRESHOLD) {
            _hasDetectedSpeech = true;
            _silenceDuration = AFTER_SPEECH_SILENCE_DURATION;
            debugPrint("Speech started! Change: $amplitudeChange");
          }
        }
        // Only count silence after speech has been detected
        else if (amplitudeChange < SILENCE_THRESHOLD) {
          _silenceCount++;
          debugPrint("Silence detected: $_silenceCount / $_silenceDuration");
          if (_silenceCount >= _silenceDuration) {
            _stopAndSendRecording();
          }
        } else {
          _silenceCount = 0;
        }

        _lastAmplitude = currentAmp;
      });
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
      if (_currentPosition != null) {
        final request = http.MultipartRequest(
          'POST',
          Uri.parse('http://192.168.51.204:8000/transcribe/'),
        );
        request.files.add(await http.MultipartFile.fromPath('file', file.path));
        request.fields['latitude'] = _currentPosition!.latitude.toString();
        request.fields['longitude'] = _currentPosition!.longitude.toString();
        request.fields['country'] = _country;

        final response = await request.send();

        if (response.statusCode == 200) {
          final text = await response.stream.bytesToString();
          setState(() => _transcription = text);
        } else {
          setState(() => _transcription = "Failed: ${response.statusCode}");
        }
      }
    } catch (e) {
      setState(() => _transcription = "Error: $e");
    }
  }

  Future<void> _getCurrentLocation() async {
    final hasPermission = await _handleLocationPermission();
    if (!hasPermission) return;

    try {
      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high
      );
      
      // Get address from coordinates
      List<Placemark> placemarks = await placemarkFromCoordinates(
        position.latitude,
        position.longitude,
      );

      if (placemarks.isNotEmpty) {
        Placemark place = placemarks[0];
        setState(() {
          _currentPosition = position;
          _country = place.country ?? "Unknown";
          _locationStatus = 'Location: ${position.latitude}, ${position.longitude}\nCountry: $_country';
        });
      }
    } catch (e) {
      setState(() => _locationStatus = 'Error getting location: $e');
    }
  }

  Future<bool> _handleLocationPermission() async {
    bool serviceEnabled;
    LocationPermission permission;

    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      setState(() => _locationStatus = 'Location services are disabled.');
      return false;
    }

    permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        setState(() => _locationStatus = 'Location permissions are denied.');
        return false;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      setState(() => _locationStatus = 'Location permissions are permanently denied.');
      return false;
    }

    return true;
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
            const SizedBox(height: 20),
            Text(
              "Location Status:",
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            Column(
              children: [
                Text(_locationStatus),
                const SizedBox(height: 10),
                ElevatedButton(
                  onPressed: _getCurrentLocation,
                  child: Text('Refresh Location'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}