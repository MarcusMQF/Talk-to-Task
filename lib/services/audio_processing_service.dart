// ignore_for_file: dead_code

import 'dart:async';
import 'dart:io';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:http_parser/http_parser.dart';

import '../services/gemini_service.dart';
import '../services/get_device_info.dart';

class AudioProcessingService {
  // Constants
  static const double SILENCE_THRESHOLD = 3.0;
  static const double AMPLITUDE_CHANGE_THRESHOLD = 50.0;
  static const int INITIAL_SILENCE_DURATION = 100;
  static const int PRE_SPEECH_SILENCE_COUNT = 100;
  static const int POST_SPEECH_SILENCE_COUNT = 10;

  static const String BASE_URL = 'https://b6a5-103-18-0-17.ngrok-free.app';
  static const String SERVER_URL = '$BASE_URL/upload/';

  // Audio recording
  final AudioRecorder _recorder = AudioRecorder();
  final GeminiService _geminiService = GeminiService();
  final DeviceInfoService _deviceInfo = DeviceInfoService();

  // State variables
  Timer? _amplitudeTimer;
  double _lastAmplitude = -30.0;
  double _currentAmplitude = -30.0;
  bool _hasDetectedSpeech = false;
  bool _isRecording = false;
  int _silenceDuration = INITIAL_SILENCE_DURATION;
  int _silenceCount = 0;
  bool _isProcessing = false;

  // Callbacks
  Function(String message)? onTranscriptionUpdate;
  Function(bool isRecording)? onRecordingStateChanged;
  Function(bool isProcessing)? onProcessingStateChanged;
  Function(String baseText, String enhancedText, String geminiResponse)?
      onTranscriptionComplete;




  // Constructor
  AudioProcessingService() {
    // Initialize in the background with better error handling
    try {
      initialize().then((_) {
        print('AudioProcessingService initialization complete');
      }).catchError((error) {
        print('AudioProcessingService initialization error: $error');
      });
    } catch (e) {
      print('Fatal error in AudioProcessingService constructor: $e');
    }
  }
  // Get temporary file path for recording
  Future<String> getTempFilePath() async {
    final dir = await getTemporaryDirectory();
    return p.join(dir.path, 'recorded_audio.wav');
  }

  Future<void> initialize() async {
    // Initialize device info service
    ProcessSignal.sigterm.watch().listen((_) {
      print('SIGTERM received - cleaning up resources');
      dispose();
    });

    print('Initializing DeviceInfoService...');
    bool locationInitialized = await _deviceInfo.initializeLocation();
    print('Location initialized: $locationInitialized');

    // Pre-fetch device context to warm up the cache
    final context = await _deviceInfo.getDeviceContext();
    print('Device context: ${context.toString()}');
  }

  // Start recording method
  Future<void> startRecording() async {
    try {
      print('\n=== Starting Recording Process ===');

      // Cancel any existing timers
      _amplitudeTimer?.cancel();
      _amplitudeTimer = null;

      // Check permission
      if (!await _recorder.hasPermission()) {
        throw Exception('Microphone permission denied');
      }

      final path = await getTempFilePath();
      print('Recording path: $path');

      // Start recording with optimized settings
      await _recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.wav,
          bitRate: 768000,
          sampleRate: 48000,
          numChannels: 2,
        ),
        path: path,
      );

      print('Recording started in WAV mode');

      // Reset state variables
      _isRecording = true;
      _hasDetectedSpeech = false;
      _silenceCount = 0;
      _silenceDuration = PRE_SPEECH_SILENCE_COUNT;
      _lastAmplitude = -30.0;
      _currentAmplitude = -30.0;

      // Notify through callback
      if (onRecordingStateChanged != null) {
        onRecordingStateChanged!(true);
      }

      if (onTranscriptionUpdate != null) {
        onTranscriptionUpdate!("Listening...");
      }

      // Start monitoring amplitude
      startAmplitudeMonitoring();
    } catch (e) {
      print('Error in startRecording: $e');
      _isRecording = false;

      if (onRecordingStateChanged != null) {
        onRecordingStateChanged!(false);
      }

      if (onTranscriptionUpdate != null) {
        onTranscriptionUpdate!("Error: Failed to start recording");
      }
    }
  }

  // Monitor audio amplitude
  void startAmplitudeMonitoring() {
    // Ensure no duplicate timers
    _amplitudeTimer?.cancel();

    int readingsToSkip = 2;
    _amplitudeTimer =
        Timer.periodic(const Duration(milliseconds: 100), (timer) async {
      if (!_isRecording) {
        print("Recording stopped, cancelling amplitude timer");
        timer.cancel();
        return;
      }

      try {
        final amplitude = await _recorder.getAmplitude();
        double newAmplitude = amplitude.current;

        // Skip invalid amplitude values
        if (newAmplitude.isInfinite || newAmplitude.isNaN) {
          print('⚠️ Skipping invalid amplitude value');
          return;
        }

        _currentAmplitude = newAmplitude;

        // Handle initial readings
        if (readingsToSkip > 0) {
          print('\n=== 🎤 Reading ${3 - readingsToSkip} Skipped ===');
          print('Amplitude: ${_currentAmplitude.toStringAsFixed(2)} dB');
          _lastAmplitude = _currentAmplitude;
          readingsToSkip--;
          return;
        }

        // Amplitude analysis
        double percentageChange = 0.0;
        if (_lastAmplitude.abs() > 0.001 && !_lastAmplitude.isInfinite) {
          percentageChange =
              ((_currentAmplitude - _lastAmplitude) / _lastAmplitude.abs()) *
                  100;
          percentageChange = percentageChange.clamp(-1000.0, 1000.0);

          print('\n=== 🎙️ Amplitude Analysis ===');
          print('Previous: ${_lastAmplitude.toStringAsFixed(2)} dB');
          print('Current:  ${_currentAmplitude.toStringAsFixed(2)} dB');
          print('Change:   ${percentageChange.toStringAsFixed(2)}%');
          print('Silence:  $_silenceCount/$_silenceDuration');

          // Speech detection
          if (percentageChange.abs() > AMPLITUDE_CHANGE_THRESHOLD) {
            if (!_hasDetectedSpeech) {
              print(
                  'Speech detected - Amplitude change: ${percentageChange.toStringAsFixed(2)}%');
              _hasDetectedSpeech = true;
              _silenceDuration = POST_SPEECH_SILENCE_COUNT;
            }
            _silenceCount = 0;
          }
          // Silence detection
          else if (_currentAmplitude < SILENCE_THRESHOLD) {
            _silenceCount++;
            if (_silenceCount >= _silenceDuration) {
              print('Recording stopped - Silence duration reached');
              timer.cancel();
              stopAndSendRecording();
            }
          } else {
            _silenceCount = 0;
          }

          _lastAmplitude = _currentAmplitude;
        }
      } catch (e) {
        print('❌ Error in amplitude monitoring: $e');
      }
    });

    print("Amplitude monitoring started");
  }

  // Stop recording and process audio
  Future<void> stopAndSendRecording() async {
    try {
      print('\n=== Stopping Recording ===');

      final path = await _recorder.stop();
      _isRecording = false;
      _isProcessing = true;

      if (onRecordingStateChanged != null) {
        onRecordingStateChanged!(false);
      }

      if (onProcessingStateChanged != null) {
        onProcessingStateChanged!(true);
      }

      if (path == null) {
        throw Exception('Recording stopped but no file path returned');
      }

      final file = File(path);
      if (!await file.exists()) {
        throw Exception('Recording file not found at: $path');
      }

      final fileSize = await file.length();
      print('Recording stopped. File size: $fileSize bytes');

      if (fileSize == 0) {
        throw Exception('Recording file is empty');
      }

      if (onTranscriptionUpdate != null) {
        onTranscriptionUpdate!("Processing audio...");
      }

      await uploadAudio(file);
    } catch (e) {
      print('Error in stopAndSendRecording: $e');
      _isProcessing = false;

      if (onProcessingStateChanged != null) {
        onProcessingStateChanged!(false);
        onTranscriptionUpdate!("Error: Failed to process recording");
      }
    }
  }

  Future<void> uploadAudio(File file) async {
    try {
      _isProcessing = true;

      final audioData = await file.readAsBytes();

      print('\n=== Starting Audio Upload Process ===');
      print('File details:');
      print('- Path: ${file.path}');
      print('- Size: ${await file.length()} bytes');
      print('📤 URL: $SERVER_URL');
      print(
          '📦 Audio size: ${(audioData.length / 1024).toStringAsFixed(2)} KB');

      final request = http.MultipartRequest('POST', Uri.parse(SERVER_URL));

      // Check if processing has been cancelled
      if (!_isProcessing) {
        print('Processing cancelled before upload, aborting');
        return;
      }

      // Add audio file
      request.files.add(
        http.MultipartFile.fromBytes(
          'file',
          audioData,
          filename: 'audio.wav',
          contentType: MediaType('audio', 'wav'),
        ),
      );

      // Get device context for country
      Map<String, dynamic> deviceContext =
          await _deviceInfo.getDeviceContext(needLocation: true);
      final country = deviceContext['location'] ??
          "Malaysia"; // Default to Malaysia if location fails

      print('📍 Using country: $country');
      request.fields['country'] = country;

      print('📱 Device context details:');
      deviceContext.forEach((key, value) {
        print('  - $key: $value');
      });

      final stopwatch = Stopwatch()..start();
      print('📤 Sending request to backend...');
      final response = await request.send().timeout(
        const Duration(seconds: 15),
        onTimeout: () {
          print('❌ Backend request timed out after 15 seconds');
          throw TimeoutException('Backend request timed out');
        },
      );

      final responseTime = stopwatch.elapsedMilliseconds;
      final responseData = await http.Response.fromStream(response);

      print('\n=== 📥 BACKEND RESPONSE ===');
      print('⏱️ Response received in ${responseTime}ms');
      print('📊 Status code: ${response.statusCode}');

      // Process the response
      if (response.statusCode == 200) {
        final jsonResponse = json.decode(responseData.body);

        // Get transcriptions
        final baseText = jsonResponse['base_model']['text'];
        final fineTunedText = jsonResponse['fine_tuned_model']?['text'] ??
            "No fine-tuned model available for $country";

        // Create Gemini prompt using the GeminiService
        final prompt = _geminiService.createGeminiPrompt(
            baseText, fineTunedText, deviceContext, country);
        print(prompt);
        print('\nWaiting for Gemini response...');
        final geminiResponse =
            await _geminiService.generateOneTimeResponse(prompt);

        print('\nGemini Response:');
        print('----------------------------------------');
        print(geminiResponse);

        _isProcessing = false;

        // Notify through callbacks
        if (onProcessingStateChanged != null) {
          onProcessingStateChanged!(false);
        }

        if (onTranscriptionComplete != null) {
          onTranscriptionComplete!(baseText, fineTunedText, geminiResponse);
        }
      } else {
        throw Exception(
            'Server returned ${response.statusCode}: ${responseData.body}');
      }
    } catch (e) {
      print('Error in audio processing: $e');
      _isProcessing = false;

      if (onProcessingStateChanged != null) {
        onProcessingStateChanged!(false);
      }

      if (onTranscriptionUpdate != null) {
        onTranscriptionUpdate!("Error: Failed to process audio");
      }
    }
  }

  // Manual methods for controlling recording
  Future<void> stopRecording() async {
    if (_isRecording) {
      _amplitudeTimer?.cancel();
      await stopAndSendRecording();
    }
  }

  Future<void> abortRecording() async {
    print('\n=== Aborting Recording ===');

    // Cancel amplitude timer first to prevent callbacks while we're aborting
    try {
      _amplitudeTimer?.cancel();
      _amplitudeTimer = null;
    } catch (e) {
      print('Error cancelling amplitude timer: $e');
    }

    // Check recording state - note the await since isRecording() returns Future<bool>
    bool wasRecording = false;
    try {
      wasRecording = await _recorder.isRecording();
      print('Recording active at abort time: $wasRecording');
    } catch (e) {
      print('Error checking recording state: $e');
      // Fall back to our internal state if we can't check the recorder
      wasRecording = _isRecording;
    }

    // Stop recording if needed
    try {
      if (wasRecording) {
        print('Stopping active recording during abort');
        final path = await _recorder.stop().timeout(const Duration(seconds: 2),
            onTimeout: () {
          print('Recorder stop timed out');
          return null;
        });

        // Try to delete the file
        if (path != null) {
          try {
            final file = File(path);
            if (await file.exists()) {
              await file.delete();
              print('Recording file deleted');
            }
          } catch (e) {
            print('Error deleting recording file: $e');
          }
        }
      }
    } catch (e) {
      print('Error stopping recorder: $e');
    }

    // Set flags AFTER stopping recording
    _isRecording = false;
    _isProcessing = false;

    // Update state via callbacks
    try {
      if (onRecordingStateChanged != null) {
        onRecordingStateChanged!(false);
      }

      if (onProcessingStateChanged != null) {
        onProcessingStateChanged!(false);
      }

      if (onTranscriptionUpdate != null) {
        onTranscriptionUpdate!("Recording aborted");
      }
    } catch (e) {
      print('Error in abort callbacks: $e');
    }
  }

  // Clean up resources
  void dispose() {
    _amplitudeTimer?.cancel();
    _recorder.dispose();
  }
}
