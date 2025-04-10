import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter/services.dart';
import 'package:http_parser/http_parser.dart';

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
  // Add server URL as a constant
  static const String SERVER_URL = 'http://10.10.13.9:8000/transcribe/';

  final AudioRecorder _recorder = AudioRecorder();
  bool _isRecording = false;
  String _transcription = "Press the mic to start speaking.";
  String _baseTranscription = "";
  String _fineTunedTranscription = "";
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
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _initializeLocation();
      // After getting location, debug print the values
      debugPrint("Current location - Country: $_country, Position: $_currentPosition");
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
      debugPrint("Starting upload process..."); // Debug log
      if (_currentPosition != null) {
        final request = http.MultipartRequest('POST', Uri.parse(SERVER_URL));
        
        // Debug log file details
        debugPrint("File path: ${file.path}");
        debugPrint("File exists: ${await file.exists()}");
        debugPrint("File size: ${await file.length()} bytes");

        // Add file
        final audioFile = await http.MultipartFile.fromPath(
          'file', 
          file.path,
          contentType: MediaType('audio', 'm4a')
        );
        request.files.add(audioFile);

        // Add location data with null checks
        request.fields.addAll({
          'latitude': _currentPosition?.latitude.toString() ?? '',
          'longitude': _currentPosition?.longitude.toString() ?? '',
          'country': _country.isNotEmpty ? _country : 'Unknown',
        });
        debugPrint("Sending request with fields: ${request.fields}"); // Debug log

        // Send request with detailed error handling
        try {
          debugPrint("Sending request to: $SERVER_URL"); // Debug log
          final streamedResponse = await request.send().timeout(
            const Duration(seconds: 30),
            onTimeout: () {
              debugPrint("Request timed out"); // Debug log
              throw TimeoutException('Request timed out');
            },
          );

          debugPrint("Got response with status: ${streamedResponse.statusCode}"); // Debug log
          final response = await http.Response.fromStream(streamedResponse);
          debugPrint("Response headers: ${response.headers}"); // Debug log
          debugPrint("Response body: ${response.body}"); // Debug log

          if (response.statusCode == 200) {
            if (response.body.isNotEmpty) {
              try {
                final jsonResponse = json.decode(response.body);
                debugPrint("Parsed JSON response: $jsonResponse"); // Debug log
                setState(() {
                  _baseTranscription = jsonResponse['base_model']?['text'] ?? "No base model transcription";
                  _fineTunedTranscription = jsonResponse['fine_tuned_model']?['text'] ?? 
                      "No fine-tuned model available for $_country";
                  _transcription = "Base Model:\n$_baseTranscription\n\nFine-tuned Model:\n$_fineTunedTranscription";
                });
              } catch (e) {
                debugPrint("JSON decode error: $e"); // Debug log
                setState(() => _transcription = "Error decoding response: $e");
              }
            } else {
              debugPrint("Empty response body"); // Debug log
              setState(() => _transcription = "Empty response from server");
            }
          } else {
            debugPrint("Server error response: ${response.statusCode} - ${response.body}"); // Debug log
            setState(() => _transcription = "Server error: ${response.statusCode}\n${response.body}");
          }
        } catch (e) {
          debugPrint("Network error: $e"); // Debug log
          setState(() => _transcription = "Network error: $e");
        }
      } else {
        debugPrint("No location available"); // Debug log
        setState(() => _transcription = "Location not available");
      }
    } catch (e, stackTrace) {
      debugPrint("Error in _uploadAudio: $e"); // Debug log
      debugPrint("Stack trace: $stackTrace"); // Debug log
      setState(() => _transcription = "Error: ${e.toString()}");
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
            const SizedBox(height: 20),
            Text("Base Model Transcription:", style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            Expanded(
              child: SingleChildScrollView(
                child: Text(_baseTranscription),
              ),
            ),
            const SizedBox(height: 20),
            Text("Fine-tuned Model Transcription:", style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            Expanded(
              child: SingleChildScrollView(
                child: Text(_fineTunedTranscription),
              ),
            ),
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
              ],
            ),
          ],
        ),
      ),
    );
  }
}