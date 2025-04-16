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

  // Server URLs
  static const String SERVER_URL = 'http://192.168.159.244:8000/transcribe';
  static const String DENOISE_URL = 'http://192.168.159.244:8000/denoise';

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
  Future<String> _getTempFilePath() async {
    final dir = await getTemporaryDirectory();
    return p.join(dir.path, 'recorded_audio.wav');
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

      final path = await _getTempFilePath();
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
      _startAmplitudeMonitoring();
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
  void _startAmplitudeMonitoring() {
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
              _stopAndSendRecording();
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
  Future<void> _stopAndSendRecording() async {
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

      await _uploadAudio(file);
    } catch (e) {
      print('Error in _stopAndSendRecording: $e');
      _isProcessing = false;

      if (onProcessingStateChanged != null) {
        onProcessingStateChanged!(false);
      }

      if (onTranscriptionUpdate != null) {
        onTranscriptionUpdate!("Error: Failed to process recording");
      }
    }
  }

// Modify the _uploadAudio method to better handle large files
  Future<void> _uploadAudio(File file) async {
    try {
      print('\n=== Starting Audio Upload Process ===');
      print('File details:');
      print('- Path: ${file.path}');
      print('- Size: ${await file.length()} bytes');

      // Check if processing has been cancelled
      if (!_isProcessing) {
        print('Processing cancelled before upload, aborting');
        return;
      }

      // For very large files, skip denoising entirely
      final fileSize = await file.length();
      List<int> audioData;

      if (fileSize > 300000) {
        print('File too large, skipping denoising completely');
        audioData = await file.readAsBytes();
      } else {
        // For smaller files, try denoising with timeout
        print('\n=== Step 1: Audio Denoising ===');
        final denoisedData = await _denoiseAudio(file);

        if (denoisedData == null || !_isProcessing) {
          print('Denoising failed or processing cancelled, aborting');
          return;
        }

        audioData = denoisedData;
      }

      // Check again if processing has been cancelled
      if (!_isProcessing) {
        print('Processing cancelled after denoising, aborting transcription');
        return;
      }

      // Step 2: Transcription
      print('\n=== Step 2: Transcription ===');
      await _transcribeAudio(audioData);
    } catch (e, stackTrace) {
      print('Error in audio processing:');
      print('Error: $e');
      print('Stack trace:\n$stackTrace');

      if (_isProcessing && onProcessingStateChanged != null) {
        onProcessingStateChanged!(false);
      }

      if (onTranscriptionUpdate != null) {
        onTranscriptionUpdate!("Error: Failed to process audio");
      }
      _isProcessing = false;
    }
  }

  Future<List<int>?> _denoiseAudio(File file) async {
    try {
      final fileSize = await file.length();
      print('File size for denoising: $fileSize bytes');

      // MUCH MORE AGGRESSIVE size limit - skip denoising for all but very small files
      if (fileSize > 150000) {
        // Lower threshold to 150KB
        print(
            'Audio file size ($fileSize bytes) exceeds threshold, skipping denoising entirely');
        return await file.readAsBytes();
      }

      // For smaller files, use a more reliable approach
      final bytes = await file.readAsBytes();

      try {
        // Set up a completer with timeout to handle the denoising operation
        final completer = Completer<List<int>>();

        // Set a timer to resolve with original audio if denoising takes too long
        final timer = Timer(const Duration(seconds: 3), () {
          if (!completer.isCompleted) {
            print(
                'Denoising operation timed out after 3 seconds, using original audio');
            completer.complete(bytes);
          }
        });

        // Start the request
        print('Sending to denoising API with strict 3-second timeout...');
        final request =
            http.MultipartRequest('POST', Uri.parse('$DENOISE_URL/'));

        request.files.add(
          http.MultipartFile.fromBytes(
            'file',
            bytes,
            filename: 'audio.wav',
            contentType: MediaType('audio', 'wav'),
          ),
        );

        // Handle the response
        final response = await request.send().timeout(
          const Duration(seconds: 3),
          onTimeout: () {
            print('HTTP request timed out, using original audio');
            throw TimeoutException('Denoising HTTP request timed out');
          },
        );

        // Cancel the timer since we got a response
        timer.cancel();

        if (response.statusCode == 200 && !completer.isCompleted) {
          final denoisedAudio = await response.stream.toBytes();
          if (denoisedAudio.isNotEmpty) {
            completer.complete(denoisedAudio);
          } else {
            completer.complete(bytes);
          }
        } else if (!completer.isCompleted) {
          completer.complete(bytes);
        }

        return await completer.future;
      } catch (e) {
        print('Denoising error: $e - Using original audio');
        return bytes;
      }
    } catch (e) {
      print('Error preparing for denoising: $e');
      return null;
    }
  }

  // Transcribe audio and process with Gemini
  Future<void> _transcribeAudio(List<int> audioData) async {
    try {
      if (onTranscriptionUpdate != null) {
        onTranscriptionUpdate!("Processing audio...");
      }

      print('Preparing transcription request...');
      final request = http.MultipartRequest('POST', Uri.parse('$SERVER_URL/'));

      request.files.add(
        http.MultipartFile.fromBytes(
          'file',
          audioData,
          filename: 'denoised_audio.wav',
          contentType: MediaType('audio', 'wav'),
        ),
      );

      // Get device context
      Map<String, dynamic> deviceContext = await _deviceInfo.getDeviceContext();
      final country = deviceContext['location'] ?? "Unknown";

      request.fields['country'] = country;
      print('Sending to transcription API...');
      print('- Audio size: ${audioData.length} bytes');
      print('- Country: $country');

      final response = await request.send();
      final responseData = await http.Response.fromStream(response);

      print('Transcription response received:');
      print('- Status code: ${response.statusCode}');

      if (response.statusCode == 200) {
        final jsonResponse = json.decode(responseData.body);
        print('Transcription successful:');
        print('- Base model: ${jsonResponse['base_model']['text']}');
        print(
            '- Fine-tuned model: ${jsonResponse['fine_tuned_model']?['text']}');

        // Get transcriptions
        final baseText = jsonResponse['base_model']['text'];
        final fineTunedText = jsonResponse['fine_tuned_model']?['text'] ??
            "No fine-tuned model available for $country";

        // Create Gemini prompt
        final prompt = _createGeminiPrompt(
            baseText, fineTunedText, deviceContext, country);

        print('\nWaiting for Gemini response...');
        final geminiResponse =
            await _geminiService.generateOneTimeResponse(prompt);

        print('\nGemini Response:');
        print('----------------------------------------');
        print(geminiResponse);

        _isProcessing = false;

        // Notify through callback
        if (onProcessingStateChanged != null) {
          onProcessingStateChanged!(false);
        }

        if (onTranscriptionComplete != null) {
          onTranscriptionComplete!(baseText, fineTunedText, geminiResponse);
        }
      } else {
        throw Exception(
            'Transcription failed: ${response.statusCode}\n${responseData.body}');
      }
    } catch (e) {
      print('\n❌ Error in transcription processing: $e');
      _isProcessing = false;

      if (onProcessingStateChanged != null) {
        onProcessingStateChanged!(false);
      }

      if (onTranscriptionUpdate != null) {
        onTranscriptionUpdate!("Error processing speech. Please try again.");
      }
    }
  }

  // Create Gemini prompt with relevant context
  String _createGeminiPrompt(String baseText, String fineTunedText,
      Map<String, dynamic> deviceContext, String country) {
    // This would normally be provided by the RideScreen
    // For now, we use placeholders
    bool isOnline = true;
    bool hasActiveRequest = false;

    return '''
    Transcript A (General Model): $baseText  
    Transcript B (Local Model): $fineTunedText  

    You are a smart, friendly voice assistant in a ride-hailing app. 
    The driver is currently ${isOnline ? "ONLINE and available for rides" : "OFFLINE and not accepting ride requests"}.
    ${hasActiveRequest ? "The driver has an active ride request waiting for acceptance." : "The driver has no pending ride requests."}

    Step 1:  
    Briefly review both transcripts. If either contains relevant info about the driver's situation (e.g., plans, concerns, questions), use it.  
    If the transcripts are unclear, irrelevant, or not related to driving, ignore them. Prioritize Transcript B if needed.

    Step 2:  
    Generate realistic driver and city data based on typical patterns and time of day:
    - Total rides completed today (e.g., 3–10)
    - Total earnings today (e.g., RM40–RM200)
    - 3 nearby areas with random demand levels: High / Medium / Low
    - Optional surge zone (1 area only, with 1.2x–1.8x multiplier)

    Use the real-time device context:
    - Location: $country  
    - Battery: ${deviceContext['battery'] ?? 'Unknown'}  
    - Network: ${deviceContext['network'] ?? 'Unknown'}  
    - Time: ${deviceContext['time'] ?? 'Unknown'}  
    - Weather: ${deviceContext['weather'] ?? 'Unknown'}  

    Step 3:  
    Create a short, natural-sounding assistant message using 2–4 of the most relevant details. You may include:
    - Suggestions on where to go next
    - Earnings or ride count updates
    - Surge opportunities
    - Battery or break reminders
    - Weather or traffic tips
    - Motivation

    Message Rules:
    - Only output step 3.
    - Speak naturally, as if voiced in-app
    - Don't repeat the same fact in different ways
    - Only include useful, moment-relevant info
    - Keep it under 3 sentences

    Final Output:  
    One friendly and helpful message that feels human and situation-aware.
    ''';
  }

  // Update Gemini prompt with ride-specific context
  Future<void> updatePromptContext({
    required bool isOnline,
    required bool hasActiveRequest,
    String? pickupLocation,
    String? pickupDetail,
    String? destination,
    String? paymentMethod,
    String? fareAmount,
    String? tripDistance,
    String? estimatedPickupTime,
    String? estimatedTripDuration,
  }) async {
    // This method would update the context used for Gemini prompts
    // The actual implementation would store these values for use in _createGeminiPrompt
  }

  // Manual methods for controlling recording
  Future<void> stopRecording() async {
    if (_isRecording) {
      _amplitudeTimer?.cancel();
      await _stopAndSendRecording();
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
