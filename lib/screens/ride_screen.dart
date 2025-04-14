import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'dart:async';
import 'package:flutter/physics.dart';
import '../constants/app_theme.dart';
import '../providers/voice_assistant_provider.dart';
import '../providers/theme_provider.dart';
import '../screens/ai_chat_screen.dart';
import 'dart:io';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:geocoding/geocoding.dart' as geocoding;
import 'package:location/location.dart';
import 'package:http_parser/http_parser.dart';
import 'package:battery_plus/battery_plus.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:intl/intl.dart';
import '../services/gemini_service.dart';
import '../services/wake_word.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'dart:typed_data';
import 'package:flutter_tts/flutter_tts.dart';
import 'dart:math';

class RideScreen extends StatefulWidget {
  const RideScreen({super.key});

  @override
  State<RideScreen> createState() => _RideScreenState();
}

class _RideScreenState extends State<RideScreen> with TickerProviderStateMixin {
  late AnimationController _slideController;
  late Animation<Alignment> _slideAnimation;
  late Animation<double> _scaleAnimation;
  late Animation<double> _widthAnimation;

  // Request card animation
  late AnimationController _requestCardController;
  late Animation<Offset> _requestCardAnimation;

  // Voice button position
  late AnimationController _voiceButtonAnimController;
  Offset _voiceButtonPosition = const Offset(300, 600);  // Will be adjusted in initState based on screen size

  bool _isOnline = false;
  bool _hasActiveRequest = false;
  bool _isProcessing = false;
  int _remainingSeconds = 15;
  Timer? _requestTimer;
  final FlutterTts _flutterTts = FlutterTts();
  bool _isSpeaking = false;
  // Google Maps controller
  GoogleMapController? _mapController;

  // Initial camera position (example coordinates - should be replaced with actual pickup location)
  static const LatLng _initialPosition =
      LatLng(3.1390, 101.6869); // KL coordinates

  // Markers for pickup and dropoff locations
  final Set<Marker> _markers = {};

  // Timer animations
  late AnimationController _timerShakeController;
  late AnimationController _timerGlowController;
  late Animation<double> _timerShakeAnimation;
  late Animation<double> _timerGlowAnimation;

  // Store provider reference for safe disposal
  late VoiceAssistantProvider _voiceProvider;

  // Voice Recognition Module
  // CHANGE YOUR LOCAL IPV4 ADDRESS HERE!!
  static const String SERVER_URL = 'http://10.167.69.221:8000/transcribe/';
  static const String DENOISE_URL = 'http://10.167.69.221:8000/denoise/';

  final AudioRecorder _recorder = AudioRecorder();
  final GeminiService _geminiService = GeminiService();
  final DeviceInfoService _deviceInfo = DeviceInfoService();
  String _transcription = "Press the mic to start speaking.";
  String _baseTranscription = "";
  String _fineTunedTranscription = "";
  String _geminiResponse = "";

  Timer? _amplitudeTimer;
  Timer? _silenceTimer;
  double _lastAmplitude = -30.0;
  double _currentAmplitude = -30.0;
  bool _hasDetectedSpeech = false;
  bool _isRecording = false;
  int _silenceDuration = INITIAL_SILENCE_DURATION;
  int _silenceCount = 0;
  static const double SILENCE_THRESHOLD = 3.0;
  static const double AMPLITUDE_CHANGE_THRESHOLD = 50.0; // 50% change threshold
  static const int INITIAL_SILENCE_DURATION = 100;
  static const int PRE_SPEECH_SILENCE_COUNT = 100; // Before speech detection
  static const int POST_SPEECH_SILENCE_COUNT = 10; // After speech detection

  final Location _location = Location();
  LocationData? _currentPosition;
  String _country = "Unknown";
  final String _pickupLocation = "Sunway Pyramid Mall, PJ";
  final String _pickupDetail = "Main entrance, near Starbucks";
  final String _destination = "KL Sentral, Kuala Lumpur";
  final String _paymentMethod = "Cash";
  final String _fareAmount = "RM 15.00";
  final String _tripDistance = "3.2 km";
  final String _estimatedPickupTime = "8 min";
  final String _estimatedTripDuration = "18 min";
  final StreamController<String> _geminiStreamController =
      StreamController<String>.broadcast();
  
  @override
  void initState() {
    super.initState();
    _setupMarkers();
    _setupAnimations();
    _setupRequestCardAnimations();
    _setupVoiceButtonAnimation();
    _setupTimerAnimation();
    _initializeLocation();
    _initializeWakeWordDetection();
    _initializeTts();
    
    // Position voice button in bottom right after layout is complete
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _positionVoiceButtonBottomRight();
      _setupVoiceCommandHandler();
    });
    
    _voiceProvider =
        Provider.of<VoiceAssistantProvider>(context, listen: false);
    Future.delayed(Duration.zero, () async {
      try {
        print('Testing file loading...');
        // Get the bundle path
        final manifestContent = await DefaultAssetBundle.of(context)
            .loadString('AssetManifest.json');
        final Map<String, dynamic> manifestMap = json.decode(manifestContent);
        print('Available assets: ${manifestMap.keys}');

        // Try loading the wake word file
        final ByteData data = await rootBundle.load('assets/hey_grab.ppn');
        print(
            '✅ Wake word file loaded successfully! Size: ${data.lengthInBytes} bytes');
      } catch (e) {
        print('❌ Failed to load wake word file: $e');
      }
    });
  }

  Future<void> _initializeTts() async {
    await _flutterTts.setLanguage("en-US");
    await _flutterTts
        .setSpeechRate(0.5); // Slightly slower for better comprehension
    await _flutterTts.setVolume(1.0);
    await _flutterTts.setPitch(1.0);

    // Set up completion listener
    _flutterTts.setCompletionHandler(() {
      setState(() {
        _isSpeaking = false;
      });
    });
  }

// Add this method to speak text
  Future<void> _speakResponse(String text) async {
    if (text.isEmpty) return;

    // Stop any ongoing speech
    if (_isSpeaking) {
      await _flutterTts.stop();
    }

    setState(() {
      _isSpeaking = true;
    });

    // Clean up the text - remove markdown formatting if needed
    String cleanText =
        text.replaceAll('*', '').replaceAll('#', '').replaceAll('_', '');

    await _flutterTts.speak(cleanText);
  }

// Add this method to stop speaking
  Future<void> _stopSpeaking() async {
    print("Explicitly stopping TTS");
    await _flutterTts.stop();
    setState(() {
      _isSpeaking = false;
    });
  }

  @override
  void dispose() {
    WakeWordService.dispose(); // Add this line
    _geminiStreamController.close();
    _slideController.dispose();
    _requestCardController.dispose();
    _voiceButtonAnimController.dispose();
    _timerShakeController.dispose();
    _timerGlowController.dispose();
    _requestTimer?.cancel();
    _mapController?.dispose();
    // Use stored reference instead of accessing through context
    _voiceProvider.removeCommandCallback();
    _flutterTts.stop();
    WakeWordService.dispose();
    _geminiStreamController.close();

    super.dispose();
  }

  Future<void> _initializeWakeWordDetection() async {
    try {
      print('Initializing wake word detection...');
      WakeWordService.onWakeWordDetected = () {
        print("🎙️ WAKE WORD DETECTED!");
        if (mounted) {
          // Make sure we're on the UI thread
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _triggerVoiceAssistant();
          });
        }
      };
      // Check if the PPC file exists first
      try {
        final ByteData data = await rootBundle.load('assets/hey_grab.ppn');
        print(
            '✅ PPC file loaded successfully! Size: ${data.lengthInBytes} bytes');
      } catch (e) {
        print('❌ Failed to load PPN file: $e');
        print(
            'Make sure "hey_grab.ppn" is in the assets folder and declared in pubspec.yaml');
        return; // Don't continue initialization if file can't be loaded
      }

      // Set up callback for wake word detection
      WakeWordService.onWakeWordDetected = () {
        // When wake word is detected, we want to trigger the voice assistant
        if (mounted) {
          // Use a microtask to avoid calling setState during build
          Future.microtask(() {
            // Trigger the voice assistant UI (same as mic button)
            _triggerVoiceAssistant();
          });
        }
      };

      // Start listening for wake words
      bool success = await WakeWordService.startListening();
      print('Wake word detection initialized: $success');

      if (!success) {
        print('Failed to initialize wake word detection');
      }
    } catch (e) {
      print('Error in wake word initialization: $e');
    }
  }

  void _triggerVoiceAssistant() {
    // This method will be called when the wake word is detected

    // Add visual feedback - briefly animate the mic button
    _voiceButtonAnimController.forward().then((_) {
      _voiceButtonAnimController.reverse();
    });

    // Reset states first
    _amplitudeTimer?.cancel();
    try {
      if (_isRecording) {
        _recorder.stop();
      }
    } catch (e) {
      print("No active recording to stop: $e");
    }

    // Set recording state
    setState(() {
      _isRecording = true;
      _isProcessing = false;
      _hasDetectedSpeech = false;
      _silenceCount = 0;
      _silenceDuration = PRE_SPEECH_SILENCE_COUNT;
      _lastAmplitude = -30.0;
      _currentAmplitude = -30.0;
      _geminiResponse = "";
    });

    // Start recording
    _startRecording();
    print("Wake word activated recording");

    // Show modal bottom sheet
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isDismissible: true,
      enableDrag: true,
      builder: (BuildContext context) {
        return _buildVoiceModal(context);
      },
    ).whenComplete(() {
      print("Modal dismissed - stopping TTS and calling abortRecord()");
      // Stop TTS explicitly before aborting recording
      _stopSpeaking();
      abortRecord();
    });
  }

  void _setupMarkers() {
    _markers.add(
      const Marker(
        markerId: MarkerId('pickup'),
        position: _initialPosition,
        infoWindow: InfoWindow(title: 'Pickup Location'),
      ),
    );
  }

  void _setupRequestCardAnimations() {
    _requestCardController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );

    _requestCardAnimation = Tween<Offset>(
      begin: const Offset(0, 1), // Start from below the screen
      end: const Offset(0, 0), // End at normal position
    ).animate(CurvedAnimation(
      parent: _requestCardController,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    ));
  }

  void _setupVoiceButtonAnimation() {
    _voiceButtonAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
  }

  void _setupTimerAnimation() {
    // Shake animation
    _timerShakeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );

    _timerShakeAnimation = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween<double>(begin: 0, end: -3)
            .chain(CurveTween(curve: Curves.elasticIn)),
        weight: 25,
      ),
      TweenSequenceItem(
        tween: Tween<double>(begin: -3, end: 3)
            .chain(CurveTween(curve: Curves.elasticIn)),
        weight: 50,
      ),
      TweenSequenceItem(
        tween: Tween<double>(begin: 3, end: 0)
            .chain(CurveTween(curve: Curves.elasticOut)),
        weight: 25,
      ),
    ]).animate(_timerShakeController);

    // Glow animation
    _timerGlowController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );

    _timerGlowAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _timerGlowController,
      curve: Curves.easeInOut,
    ));

    // Loop the glow effect
    _timerGlowController.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        _timerGlowController.reverse();
      } else if (status == AnimationStatus.dismissed) {
        _timerGlowController.forward();
      }
    });
  }

  void _snapVoiceButtonToEdge() {
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;

    // Constrain Y position to be within safe bounds
    double safeY = _voiceButtonPosition.dy.clamp(
      120.0, // Stay below top toggle
      screenHeight - 100.0, // Stay above bottom edge
    );

    // Determine which side to snap to
    final isLeftHalf = _voiceButtonPosition.dx < (screenWidth / 2);
    final targetX =
        isLeftHalf ? 20.0 : screenWidth - 84.0; // 84 = button width + margin

    setState(() {
      _voiceButtonPosition = Offset(targetX, safeY);
    });
  }

  void _setupAnimations() {
    _slideController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );

    // Create a custom curve that emphasizes the bounce
    final customCurve = CurvedAnimation(
      parent: _slideController,
      curve: const Interval(0.0, 0.8, curve: Curves.easeInOutCubic),
    );

    _slideAnimation = AlignmentTween(
      begin: Alignment.centerLeft,
      end: Alignment.centerRight,
    ).animate(customCurve);

    // Create a custom curved animation for consistent behavior
    final curvedAnimation = CurvedAnimation(
      parent: _slideController,
      curve: const Interval(0.0, 1.0, curve: Curves.easeInOutCubic),
      reverseCurve: const Interval(0.0, 1.0, curve: Curves.easeInOutCubic),
    );

    // Scale animation for the water droplet effect
    _scaleAnimation = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween<double>(begin: 1.0, end: 0.85)
            .chain(CurveTween(curve: Curves.easeOut)),
        weight: 30,
      ),
      TweenSequenceItem(
        tween: Tween<double>(begin: 0.85, end: 1.1)
            .chain(CurveTween(curve: Curves.easeInOut)),
        weight: 40,
      ),
      TweenSequenceItem(
        tween: Tween<double>(begin: 1.1, end: 1.0)
            .chain(CurveTween(curve: Curves.elasticOut)),
        weight: 30,
      ),
    ]).animate(curvedAnimation);

    // Width animation for the stretching effect
    _widthAnimation = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween<double>(begin: 96, end: 110)
            .chain(CurveTween(curve: Curves.easeOut)),
        weight: 40,
      ),
      TweenSequenceItem(
        tween: Tween<double>(begin: 110, end: 96)
            .chain(CurveTween(curve: Curves.elasticOut)),
        weight: 60,
      ),
    ]).animate(curvedAnimation);
  }

  void _handleDragEnd(DragEndDetails details) {
    if (details.primaryVelocity == null) return;

    final bool isDraggingRight = details.primaryVelocity! > 0;
    final bool shouldToggle =
        (isDraggingRight && !_isOnline) || (!isDraggingRight && _isOnline);

    if (shouldToggle) {
      _toggleOnlineStatus();
    }

    // Create identical spring simulation for both directions
    const spring = SpringDescription(
      mass: 1,
      stiffness: 500,
      damping: 20,
    );

    final double velocity = details.primaryVelocity! / 1000;
    final double currentValue = _slideController.value;
    final double targetValue =
        shouldToggle ? (isDraggingRight ? 1.0 : 0.0) : (_isOnline ? 1.0 : 0.0);

    final simulation = SpringSimulation(
      spring,
      currentValue,
      targetValue,
      velocity,
    );

    _slideController.animateWith(simulation);
  }

  void _startRequestTimer() {
    _remainingSeconds = 15;
    _requestTimer?.cancel();
    _requestTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      setState(() {
        if (_remainingSeconds > 0) {
          _remainingSeconds--;

          // Start urgent animations when less than or equal to 5 seconds remaining
          if (_remainingSeconds <= 5) {
            if (!_timerGlowController.isAnimating) {
              _timerGlowController.forward();
            }
            _timerShakeController.forward(from: 0.0);
          }
        } else {
          // Time's up - animate the request card sliding out
          _dismissRequest();
          timer.cancel();

          // Simulate new request after timeout
          Future.delayed(const Duration(seconds: 2), () {
            if (_isOnline) {
              _showNewRequest();
            }
          });
        }
      });
    });
  }

  void _showNewRequest() {
    setState(() {
      _hasActiveRequest = true;
      _requestCardController.forward(from: 0.0);
      _startRequestTimer();
    });
  }

  void _dismissRequest() {
    // Make sure controller is initialized before animating
    if (!_requestCardController.isAnimating) {
      _requestCardController.reverse().then((_) {
        if (mounted) {
          setState(() {
            _hasActiveRequest = false;
          });
        }
      });
    }
  }
void _toggleOnlineStatus() {
  // Always update the online state immediately for smooth toggle animation
  setState(() {
    _isOnline = !_isOnline;
    
    // AI STATUS INDICATOR - This comment helps the AI know the driver's status
    // Driver is currently: ${_isOnline ? "ONLINE" : "OFFLINE"}
    
    if (_isOnline) {
      // Going online - show request card with animation
      _showNewRequest();
    } else {
      // Going offline - but keep request card visible for animation
      if (_hasActiveRequest) {
        // Keep _hasActiveRequest true until animation completes
        _dismissRequest();
        _requestTimer?.cancel();
      }
    }
  });
}

  Future<void> _initializeLocation() async {
    await _getCurrentLocation();
  }

  Future<String> _getTempFilePath() async {
    final dir = await getTemporaryDirectory();
    return p.join(dir.path, 'recorded_audio.wav'); // Changed from .m4a to .wav
  }

  Future<void> _startRecording() async {
    try {
      print('\n=== Starting Recording Process ===');

      // Cancel any existing timers first
      _amplitudeTimer?.cancel();
      _amplitudeTimer = null;

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

      print('Recording started in mono WAV mode');

      // Set recording state variables
      setState(() {
        _isRecording = true;
        _hasDetectedSpeech = false;
        _silenceCount = 0;
        _silenceDuration = PRE_SPEECH_SILENCE_COUNT;
        _lastAmplitude = -30.0;
        _currentAmplitude = -30.0;
        _transcription = "Listening...";
      });

      print("Starting amplitude monitoring...");
      _startAmplitudeMonitoring();
    } catch (e) {
      print('Error in _startRecording: $e');
      setState(() {
        _isRecording = false;
        _transcription = "Error: Failed to start recording";
      });
      rethrow; // Important to propagate the error
    }
  }

  void _startAmplitudeMonitoring() {
    // Ensure we don't have multiple timers
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

        setState(() {
          _currentAmplitude = newAmplitude;
        });

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
              setState(() {
                _hasDetectedSpeech = true;
                _silenceDuration = POST_SPEECH_SILENCE_COUNT;
              });
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

  Future<void> _stopAndSendRecording() async {
    try {
      print('\n=== Stopping Recording ===');
      _silenceTimer?.cancel();

      final path = await _recorder.stop();
      setState(() {
        _isRecording = false;
        _isProcessing = true; // Set processing state
      });

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

      setState(() => _transcription = "Processing audio...");
      await _uploadAudio(file);
    } catch (e) {
      print('Error in _stopAndSendRecording: $e');
      setState(() {
        _transcription = "Error: Failed to process recording";
        _isProcessing = false;
      });
    }
  }

  // Update the _uploadAudio method to handle denoising failures
  Future<void> _uploadAudio(File file) async {
    try {
      print('\n=== Starting Audio Upload Process ===');
      print('File details:');
      print('- Path: ${file.path}');
      print('- Exists: ${await file.exists()}');
      print('- Size: ${await file.length()} bytes');

      // Step 1: Denoising
      print('\n=== Step 1: Audio Denoising ===');
      List<int>? audioData = await _denoiseAudio(file);

      if (audioData == null) {
        print('Denoising failed, using original audio');
        audioData = await file.readAsBytes();
      }

      // Step 2: Transcription
      print('\n=== Step 2: Transcription ===');
      await _transcribeAudio(audioData);
    } catch (e, stackTrace) {
      print('Error in audio processing:');
      print('Error: $e');
      print('Stack trace:\n$stackTrace');
      setState(() {
        _transcription = "Error: Failed to process audio";
        _isProcessing = false;
      });
    }
  }

  Future<List<int>?> _denoiseAudio(File file) async {
    int retryCount = 0;
    const maxRetries = 3;
    const retryDelay = Duration(seconds: 1);

    while (retryCount < maxRetries) {
      try {
        print('\n=== Starting Denoising (Attempt ${retryCount + 1}) ===');
        print('Input file details:');
        print('- Path: ${file.path}');
        final fileSize = await file.length();
        print('- Size: $fileSize bytes');

        if (fileSize == 0) {
          throw Exception('Audio file is empty');
        }

        // Validate WAV file header
        final bytes = await file.readAsBytes();
        if (bytes.length < 44) {
          throw Exception('Invalid WAV file: too small');
        }

        final request = http.MultipartRequest('POST', Uri.parse(DENOISE_URL));
        // Second addition with same 'file' name
        final audioFile = await http.MultipartFile.fromPath(
          'file',
          file.path,
          contentType: MediaType('application', 'octet-stream'),
        );
        request.files.add(audioFile);

        // Add error tracking headers
        request.headers.addAll({
          'X-Retry-Count': retryCount.toString(),
          'X-Client-Version': '1.0.0',
          'X-File-Size': fileSize.toString(),
        });

        print('Sending to denoising API...');
        print('- File size: ${audioFile.length} bytes');
        print('- Content type: ${audioFile.contentType}');
        print('- Retry count: $retryCount');

        final response = await request.send().timeout(
              const Duration(seconds: 30),
              onTimeout: () =>
                  throw TimeoutException('Denoising request timed out'),
            );

        if (response.statusCode == 200) {
          final denoisedAudio = await response.stream.toBytes();
          print('Denoised audio received: ${denoisedAudio.length} bytes');

          if (denoisedAudio.isEmpty) {
            throw Exception('Received empty audio data');
          }

          return denoisedAudio;
        } else {
          final error = await response.stream.bytesToString();
          throw Exception('Denoising failed (${response.statusCode}): $error');
        }
      } catch (e) {
        print('Error in denoising (Attempt ${retryCount + 1}): $e');

        if (retryCount < maxRetries - 1) {
          print('Retrying in ${retryDelay.inSeconds} seconds...');
          await Future.delayed(retryDelay);
          retryCount++;
        } else {
          // If all retries failed, try to proceed without denoising
          print(
              'All denoising attempts failed. Proceeding with original audio...');
          return await file.readAsBytes();
        }
      }
    }

    // If we reach here, all retries failed
    return null;
  }

  Future<void> _transcribeAudio(List<int> audioData) async {
    setState(() {
      _isProcessing = true;
      _transcription = "Processing audio...";
    });

    try {
      print('Preparing transcription request...');
      final request = http.MultipartRequest('POST', Uri.parse(SERVER_URL));

      request.files.add(
        http.MultipartFile.fromBytes(
          'file',
          audioData,
          filename: 'denoised_audio.wav',
          contentType: MediaType('audio', 'wav'),
        ),
      );

      request.fields['country'] = _country;
      print('Sending to transcription API...');
      print('- Audio size: ${audioData.length} bytes');
      print('- Country: $_country');

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
            "No fine-tuned model available for $_country";

        // Get real-time device context
        final deviceContext = await _deviceInfo.getDeviceContext();

        // Create Gemini prompt with dynamic device info
        final prompt = '''
        Transcript A (General Model): $baseText  
        Transcript B (Local Model): $fineTunedText  

        You are a smart, friendly voice assistant in a ride-hailing app. 
        The driver is currently ${_isOnline ? "ONLINE and available for rides" : "OFFLINE and not accepting ride requests"}.
        ${_hasActiveRequest ? "The driver has an active ride request waiting for acceptance." : "The driver has no pending ride requests."}

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
        - Location: ${_country}  
        - Battery: ${deviceContext['battery']}  
        - Network: ${deviceContext['network']}  
        - Time: ${deviceContext['time']}  
        - Weather: ${deviceContext['weather']}  

        You are a smart, friendly voice assistant in a ride-hailing app. 
        The driver is currently ${_isOnline ? "ONLINE and available for rides" : "OFFLINE and not accepting ride requests"}.
        ${_hasActiveRequest ? "The driver has an active ride request waiting for acceptance." : "The driver has no pending ride requests."}

        ${_hasActiveRequest ? """
        Current ride request details:
        - Pickup: $_pickupLocation ($_pickupDetail)
        - Destination: $_destination
        - Payment method: $_paymentMethod
        - Fare amount: $_fareAmount
        - Trip distance: $_tripDistance
        - Estimated pickup time: $_estimatedPickupTime
        - Estimated trip duration: $_estimatedTripDuration
        """ : ""}
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

        print(prompt);
        print('\nWaiting for Gemini response...');

        final geminiResponse =
            await _geminiService.generateOneTimeResponse(prompt);

        print('\nGemini Response:');
        print('----------------------------------------');
        print(geminiResponse);

        setState(() {
          _baseTranscription = baseText;
          _fineTunedTranscription = fineTunedText;
          _geminiResponse = geminiResponse;
          _geminiStreamController.add(geminiResponse);
          _isProcessing = false; // Important to set this to false!
        });

        _speakResponse(geminiResponse);
      } else {
        throw Exception(
            'Transcription failed: ${responseData.statusCode}\n${responseData.body}');
      }
    } catch (e) {
      print('\n❌ Error in Gemini processing:');
      print(e);
      rethrow;
    }
    setState(() {
      _isSpeaking = false;
    });
  }

  Future<void> _handleLocationPermission() async {
    bool serviceEnabled;
    PermissionStatus permissionGranted;

    serviceEnabled = await _location.serviceEnabled();
    if (!serviceEnabled) {
      serviceEnabled = await _location.requestService();
      if (!serviceEnabled) {
        return;
      }
    }

    permissionGranted = await _location.hasPermission();
    if (permissionGranted == PermissionStatus.denied) {
      permissionGranted = await _location.requestPermission();
      if (permissionGranted != PermissionStatus.granted) {
        return;
      }
    }
  }

  Future<void> _getCurrentLocation() async {
    await _handleLocationPermission();

    try {
      final locationData = await _location.getLocation();
      _currentPosition = locationData;

      List<geocoding.Placemark> placemarks =
          await geocoding.placemarkFromCoordinates(
        locationData.latitude!,
        locationData.longitude!,
      );

      if (placemarks.isNotEmpty) {
        geocoding.Placemark place = placemarks[0];
        String rawCountry = place.country ?? "Unknown";

        final countryMapping = {
          'Malaysia': 'Malaysia',
          'Singapore': 'Singapore',
          'Thailand': 'Thailand',
          'Indonesia': 'Indonesia',
        };

        setState(() {
          _country = countryMapping[rawCountry] ?? rawCountry;
          
          // Move map camera to current position if available
          if (_mapController != null && _currentPosition != null) {
            _mapController!.animateCamera(
              CameraUpdate.newLatLng(
                LatLng(_currentPosition!.latitude!, _currentPosition!.longitude!),
              ),
            );
          }
        });
      }
    } catch (e) {
    }
  }

  // Helper method to get flag asset based on country
  String _getCountryFlagAsset() {
    switch (_country) {
      case 'Malaysia':
        return 'assets/icons/mas.png';
      case 'Singapore':
        return 'assets/icons/sg.png';
      case 'Indonesia':
        return 'assets/icons/indo.png';
      default:
        return 'assets/icons/mas.png'; // Default to Malaysia flag
    }
  }

  Future<void> abortRecord() async {
    try {
      print('\n=== Aborting Recording ===');
      await _stopSpeaking();
      // Cancel the amplitude timer to prevent memory leaks
      _amplitudeTimer?.cancel();
      _amplitudeTimer = null;

      // Stop the recording ONLY ONCE (remove the redundant code)
      if (_isRecording) {
        final path = await _recorder.stop();

        // Delete the recorded file
        if (path != null) {
          final file = File(path);
          if (await file.exists()) {
            await file.delete();
            print('Recording file deleted: $path');
          }
        }
      }

      // Reset all states
      setState(() {
        _isRecording = false;
        _isProcessing = false;
        _hasDetectedSpeech = false;
        _silenceCount = 0;
        _transcription = "Recording aborted.";
        _geminiResponse = "";
        _isSpeaking = false;
      });
    } catch (e) {
      print('Error in abortRecord: $e');
      setState(() {
        _isRecording = false;
        _isProcessing = false;
        _transcription = "Error: Failed to abort recording.";
        _isSpeaking = false;
      });
    }
  }

  Widget _buildOnlineToggle() {
    return Positioned(
      top: 48,
      left: 0,
      right: 0,
      child: Center(
        child: Container(
          width: 200,
          height: 48,
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.1),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: GestureDetector(
            onHorizontalDragUpdate: (details) {
              // Calculate drag progress and update controller
              final RenderBox box = context.findRenderObject() as RenderBox;
              final double progress =
                  (details.localPosition.dx / box.size.width).clamp(0.0, 1.0);
              _slideController.value = progress;
            },
            onHorizontalDragEnd: _handleDragEnd,
            child: Stack(
              children: [
                // Background text
                Row(
                  children: [
                    Expanded(
                      child: Center(
                        child: Text(
                          'OFFLINE',
                          style: TextStyle(
                            color: !_isOnline
                                ? Colors.grey[400]
                                : Colors.grey[300],
                            fontWeight: FontWeight.w600,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      child: Center(
                        child: Text(
                          'ONLINE',
                          style: TextStyle(
                            color:
                                _isOnline ? Colors.grey[400] : Colors.grey[300],
                            fontWeight: FontWeight.w600,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                // Animated sliding button with water droplet effect
                AnimatedBuilder(
                  animation: _slideController,
                  builder: (context, child) {
                    return Align(
                      alignment: _slideAnimation.value,
                      child: Transform.scale(
                        scale: _scaleAnimation.value,
                        child: Container(
                          width: _widthAnimation.value,
                          height: 40,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: _isOnline
                                  ? [
                                      AppTheme.grabGreen,
                                      AppTheme.grabGreen.withOpacity(0.8)
                                    ]
                                  : [
                                      Colors.grey[400]!,
                                      Colors.grey[400]!.withOpacity(0.8)
                                    ],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            borderRadius: BorderRadius.circular(20),
                            boxShadow: [
                              BoxShadow(
                                color: (_isOnline
                                        ? AppTheme.grabGreen
                                        : Colors.grey[400]!)
                                    .withOpacity(0.3),
                                blurRadius: 8,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Center(
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.circle,
                                  color: _isOnline
                                      ? Colors.white
                                      : const Color.fromARGB(
                                          255, 126, 125, 125),
                                  size: 12,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  _isOnline ? 'ONLINE' : 'OFFLINE',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
                // Touch target
                Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () {
                      _toggleOnlineStatus();
                      if (!_isOnline) {
                        _slideController.reverse();
                      } else {
                        _slideController.forward();
                      }
                    },
                    borderRadius: BorderRadius.circular(24),
                    splashColor: Colors.transparent,
                    highlightColor: Colors.transparent,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildRequestCard() {
    if (!_hasActiveRequest) return const SizedBox.shrink();

    // Determine timer color and style based on remaining time
    final bool isUrgent = _remainingSeconds <= 5;
    final Color timerColor = isUrgent ? Colors.red : AppTheme.grabGreen;

    return AnimatedBuilder(
      animation: _requestCardAnimation,
      builder: (context, child) {
        return Positioned(
          bottom: 0,
          left: 0,
          right: 0,
          child: SlideTransition(
            position: _requestCardAnimation,
            child: child!,
          ),
        );
      },
      child: Container(
        margin: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 10,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Timer indicator - more prominent with progress bar
            Container(
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                color: isUrgent
                    ? Colors.red.withOpacity(0.1)
                    : AppTheme.grabGreen.withOpacity(0.1),
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(16)),
              ),
              child: Column(
                children: [
                  // Animated timer row
                  AnimatedBuilder(
                    animation: Listenable.merge(
                        [_timerShakeAnimation, _timerGlowAnimation]),
                    builder: (context, child) {
                      return Transform.translate(
                        offset: isUrgent
                            ? Offset(_timerShakeAnimation.value, 0)
                            : Offset.zero,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            // Animated timer icon with glow effect for urgency
                            Container(
                              decoration: isUrgent
                                  ? BoxDecoration(
                                      shape: BoxShape.circle,
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.red.withOpacity(0.3 +
                                              (_timerGlowAnimation.value *
                                                  0.5)),
                                          blurRadius: 8 +
                                              (_timerGlowAnimation.value * 8),
                                          spreadRadius: 1 +
                                              (_timerGlowAnimation.value * 2),
                                        ),
                                      ],
                                    )
                                  : null,
                              child: Icon(
                                Icons.timer,
                                size: 15,
                                color: timerColor,
                              ),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              '$_remainingSeconds seconds to respond',
                              style: TextStyle(
                                color: timerColor,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 6),
                  // Progress bar for timer
                  Container(
                    margin: const EdgeInsets.symmetric(horizontal: 16),
                    height: 4,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(2),
                      child: LinearProgressIndicator(
                        value:
                            _remainingSeconds / 15, // Assuming 15 seconds total
                        backgroundColor:
                            const Color.fromARGB(255, 255, 255, 255),
                        valueColor: AlwaysStoppedAnimation<Color>(
                            isUrgent ? Colors.red : AppTheme.grabGreen),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Trip type and customer info row
                  Row(
                    children: [
                      // Trip type badge
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: AppTheme.grabGreen.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text(
                          'GrabCar',
                          style: TextStyle(
                            color: AppTheme.grabGreen,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      // Customer rating
                      const Row(
                        children: [
                          Icon(Icons.star, color: Colors.amber, size: 16),
                          SizedBox(width: 2),
                          Text(
                            '4.8',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                      const Spacer(),
                      // Payment method
                      Row(
                        children: [
                          Icon(Icons.payment,
                              size: 16, color: Colors.grey.shade700),
                          const SizedBox(width: 4),
                          Text(
                            _paymentMethod,
                            style: TextStyle(
                              color: Colors.grey.shade700,
                              fontWeight: FontWeight.w500,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),

                  const SizedBox(height: 16),

                  // Fare and distance/time row
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      // Fare with larger font
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _fareAmount,
                            style: const TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.grabGreen,
                            ),
                          ),
                          // Estimated time
                          Text(
                            'Est. $_tripDistance away',
                            style: TextStyle(
                              color: Colors.grey.shade600,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                      // Distance and ETA info
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.near_me,
                                  size: 14, color: Colors.grey.shade600),
                              const SizedBox(width: 4),
                              Text(
                                "$_estimatedTripDuration trip",
                                style: const TextStyle(
                                  color: AppTheme.grabGrayDark,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 2),
                          Row(
                            children: [
                              Icon(Icons.access_time,
                                  size: 14, color: Colors.grey.shade600),
                              const SizedBox(width: 4),
                              Text(
                                'ETA: $_estimatedPickupTime',
                                style: TextStyle(
                                  color: Colors.grey.shade600,
                                  fontWeight: FontWeight.w500,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ],
                  ),

                  const SizedBox(height: 20),

                  // Navigation card with map preview
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      children: [
                        // Quick navigation actions
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceAround,
                          children: [
                            _buildNavigationAction(
                              icon: Icons.directions,
                              label: 'Directions',
                              onTap: () {
                                if (_mapController != null) {
                                  _mapController!.animateCamera(
                                    CameraUpdate.newCameraPosition(
                                      const CameraPosition(
                                        target: _initialPosition,
                                        zoom: 16,
                                        tilt: 45,
                                      ),
                                    ),
                                  );
                                }
                              },
                            ),
                            _buildNavigationAction(
                              icon: Icons.call,
                              label: 'Call',
                              onTap: _showCallDialog,
                            ),
                            _buildNavigationAction(
                              icon: Icons.message,
                              label: 'Message',
                              onTap: () {},
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 20),

                  // Location details
                  IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Left side - Icons and connecting line
                        SizedBox(
                          width: 36,
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.spaceAround,
                            children: [
                              const SizedBox(height: 11),
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: AppTheme.grabGreen.withOpacity(0.1),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.location_on,
                                  color: AppTheme.grabGreen,
                                  size: 20,
                                ),
                              ),
                              Expanded(
                                child: Center(
                                  child: Container(
                                    width: 2,
                                    color: Colors.grey.shade300,
                                  ),
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: AppTheme.grabGreen.withOpacity(0.1),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.flag,
                                  color: AppTheme.grabGreen,
                                  size: 20,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 15),
                        // Right side - Text content
                        const Expanded(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Pickup text
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Pickup',
                                    style: TextStyle(
                                      color: Colors.grey,
                                      fontSize: 12,
                                    ),
                                  ),
                                  Text(
                                    'Sunway Pyramid Mall, PJ',
                                    style: TextStyle(
                                      color: AppTheme.grabBlack,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                  Text(
                                    'Main entrance, near Starbucks',
                                    style: TextStyle(
                                      color: Colors.grey,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),

                              SizedBox(height: 35),

                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Destination',
                                    style: TextStyle(
                                      color: Colors.grey,
                                      fontSize: 12,
                                    ),
                                  ),
                                  Text(
                                    'KL Sentral, Kuala Lumpur',
                                    style: TextStyle(
                                      color: AppTheme.grabBlack,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 20),

                  // Accept/Decline buttons
                  Row(
                    children: [
                      // Decline button
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () {
                            _dismissRequest();
                            // Simulate new request after a delay
                            Future.delayed(const Duration(seconds: 3), () {
                              if (_isOnline && mounted) {
                                _showNewRequest();
                              }
                            });
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.white,
                            foregroundColor: AppTheme.grabGrayDark,
                            elevation: 0,
                            side: BorderSide(color: Colors.grey.shade300),
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          child: const Text(
                            'Decline',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      // Accept button
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () {
                            _dismissRequest();
                            Future.delayed(const Duration(milliseconds: 500),
                                () {
                              setState(() {});
                            });
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.grabGreen,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          child: const Text(
                            'Accept',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNavigationAction({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Icon(icon, color: AppTheme.grabGreen, size: 20),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: Colors.grey.shade700,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMapControls() {
    final isDark = Provider.of<ThemeProvider>(context).isDarkMode;

    return Positioned(
      right: 16,
      top: 160,
      child: Column(
        children: [
          // My location button - separated with its own container
          Container(
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
              color: isDark ? AppTheme.grabBlack : Colors.white,
              borderRadius: BorderRadius.circular(8),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () {
                  if (_mapController != null) {
                    // If there's an active request/order, move the map view higher
                    if (_hasActiveRequest) {
                      final adjustedPosition = LatLng(
                          _initialPosition.latitude -
                              0.005, // Move up on the map
                          _initialPosition.longitude);

                      _mapController!.animateCamera(
                        CameraUpdate.newCameraPosition(
                          CameraPosition(
                            target: adjustedPosition,
                            zoom: 16, // Slightly more zoomed in
                          ),
                        ),
                      );
                    } else {
                      // Center on user's location normally
                      _mapController!.animateCamera(
                        CameraUpdate.newCameraPosition(
                          const CameraPosition(
                            target: _initialPosition,
                            zoom: 15,
                          ),
                        ),
                      );
                    }
                  }
                },
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  padding: const EdgeInsets.all(8),
                  width: 40,
                  height: 40,
                  child: const Icon(Icons.my_location,
                      color: AppTheme.grabGreen, size: 20),
                ),
              ),
            ),
          ),

          // Zoom controls in a separate container
          Container(
            decoration: BoxDecoration(
              color: isDark ? AppTheme.grabBlack : Colors.white,
              borderRadius: BorderRadius.circular(8),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              children: [
                // Zoom in button
                Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () {
                      if (_mapController != null) {
                        _mapController!.animateCamera(CameraUpdate.zoomIn());
                      }
                    },
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(8),
                      topRight: Radius.circular(8),
                    ),
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      width: 40,
                      height: 40,
                      child: const Icon(Icons.add,
                          color: AppTheme.grabGreen, size: 20),
                    ),
                  ),
                ),

                const Divider(
                    height: 1, thickness: 1, color: Color(0xFFEEEEEE)),

                // Zoom out button
                Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () {
                      if (_mapController != null) {
                        _mapController!.animateCamera(CameraUpdate.zoomOut());
                      }
                    },
                    borderRadius: const BorderRadius.only(
                      bottomLeft: Radius.circular(8),
                      bottomRight: Radius.circular(8),
                    ),
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      width: 40,
                      height: 40,
                      child: const Icon(Icons.remove,
                          color: AppTheme.grabGreen, size: 20),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          GoogleMap(
            initialCameraPosition: const CameraPosition(
              target: _initialPosition,
              zoom: 15,
            ),
            onMapCreated: (GoogleMapController controller) {
              _mapController = controller;
            },
            markers: _markers,
            myLocationEnabled: true,
            myLocationButtonEnabled: false,
            zoomControlsEnabled: false,
            mapToolbarEnabled: false,
            compassEnabled: true,
          ),
          _buildOnlineToggle(),
          if (_isOnline) _buildRequestCard(),
          _buildMapControls(),
          _buildDraggableVoiceButton(),

          // Country flag indicator
          Positioned(
            top: 55,  // Adjust this value to move up/down
            left: 25,  // Adjust this value to move left/right
            child: GestureDetector(
              onTap: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Location: $_country')),
                );
              },
              child: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.1),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: Image.asset(
                    _getCountryFlagAsset(),
                    fit: BoxFit.cover,
                  ),
                ),
              ),
            ),
          ),

          // AI Chat button positioned at top right
          Positioned(
            top: 53,
            right: 16,
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: AppTheme.grabGreen,
                borderRadius: BorderRadius.circular(11),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(15),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (context) => const AIChatScreen()),
                    );
                  },
                  child: const Center(
                    child: Icon(Icons.chat, color: Colors.white, size: 20),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // MIC BUTTON
  Widget _buildDraggableVoiceButton() {
    return Positioned(
      left: _voiceButtonPosition.dx,
      top: _voiceButtonPosition.dy,
      child: GestureDetector(
        onPanUpdate: (details) {
          setState(() {
            _voiceButtonPosition = Offset(
              _voiceButtonPosition.dx + details.delta.dx,
              _voiceButtonPosition.dy + details.delta.dy,
            );
          });
        },
        onPanEnd: (details) {
          _snapVoiceButtonToEdge();
        },
        child: Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.white,
            boxShadow: [
              BoxShadow(
                color: AppTheme.grabGreen.withOpacity(0.2),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () async {
                // Reset states first
                _amplitudeTimer?.cancel();
                try {
                  if (_isRecording) {
                    await _recorder.stop();
                  }
                } catch (e) {
                  print("No active recording to stop: $e");
                }

                // Important: set _isRecording BEFORE showing modal
                setState(() {
                  _isRecording = true;
                  _isProcessing = false;
                  _hasDetectedSpeech = false;
                  _silenceCount = 0;
                  _silenceDuration = PRE_SPEECH_SILENCE_COUNT;
                  _lastAmplitude = -30.0;
                  _currentAmplitude = -30.0;
                  _geminiResponse = ""; // Clear previous responses
                });

                try {
                  await _startRecording();
                  print("Recording started, amplitude monitoring should begin");
                } catch (e) {
                  print("Error starting recording: $e");
                  setState(() {
                    _isRecording = false;
                  });
                }
                // Show modal bottom sheet with a completely different approach
                showModalBottomSheet(
                  context: context,
                  backgroundColor: Colors.transparent,
                  isDismissible: true,
                  enableDrag: true,
                  builder: (BuildContext context) {
                    return _buildVoiceModal(context);
                  },
                ).whenComplete(() async {
                  print("Modal dismissed - calling abortRecord()");
                  await _flutterTts.stop();
                  setState(() {
                    _isSpeaking = false;
                  });
                  abortRecord();
                });
              },
              customBorder: const CircleBorder(),
              child: const Center(
                child: Icon(
                  Icons.mic,
                  color: AppTheme.grabGreen,
                  size: 28,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

// Extract the modal into a separate method
  Widget _buildVoiceModal(BuildContext context) {
    return StatefulBuilder(
      builder: (BuildContext context, StateSetter modalSetState) {
        // This function will refresh the modal with current state
        void updateModalState() {
          modalSetState(() {});
        }

        WidgetsBinding.instance.addPostFrameCallback((_) {
          Future.delayed(Duration(milliseconds: 500), () {
            if (context.mounted) updateModalState();
          });
        });

        return StreamBuilder<String>(
          stream: _geminiStreamController.stream,
          initialData: _geminiResponse,
          builder: (context, snapshot) {
            return Container(
              width: double.infinity,
              height: 300,
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(
                  top: Radius.circular(20),
                ),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (_isRecording)
                    Column(
                      children: [
                        const Icon(
                          Icons.mic,
                          color: AppTheme.grabGreen,
                          size: 48,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          _transcription,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w500,
                            color: Colors.grey,
                          ),
                        ),
                      ],
                    )
                  else if (_isProcessing)
                    const Column(
                      children: [
                        CircularProgressIndicator(
                          valueColor:
                              AlwaysStoppedAnimation<Color>(AppTheme.grabGreen),
                        ),
                        SizedBox(height: 12),
                        Text(
                          "Processing...",
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w500,
                            color: Colors.grey,
                          ),
                        ),
                      ],
                    )
                  else if (snapshot.hasData && snapshot.data!.isNotEmpty)
                    Expanded(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(23),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (_baseTranscription.isNotEmpty) ...[
                              const Text(
                                "Your speech:",
                                style: TextStyle(
                                  fontSize: 14, 
                                  fontWeight: FontWeight.bold,
                                  color: Colors.grey,
                                ),
                              ),
                              Text(
                                _baseTranscription,
                                style: const TextStyle(
                                  fontSize: 14,
                                  color: Colors.grey,
                                  fontStyle: FontStyle.italic,
                                ),
                              ),
                              const SizedBox(height: 12),
                            ],
                            if (_fineTunedTranscription.isNotEmpty && _fineTunedTranscription != _baseTranscription) ...[
                              const Text(
                                "Enhanced recognition:",
                                style: TextStyle(
                                  fontSize: 14, 
                                  fontWeight: FontWeight.bold,
                                  color: Colors.grey,
                                ),
                              ),
                              Text(
                                _fineTunedTranscription,
                                style: const TextStyle(
                                  fontSize: 14,
                                  color: AppTheme.grabGreen,
                                  fontStyle: FontStyle.italic,
                                ),
                              ),
                              const SizedBox(height: 12),
                            ],
                            Text(
                              snapshot.data!,
                              style: const TextStyle(
                                fontSize: 16,
                                color: Colors.grey,
                                height: 1.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                  else
                    const Text(
                      "No data available",
                      style: TextStyle(
                        fontSize: 16,
                        color: Colors.grey,
                      ),
                    ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  // Set up voice command handler
  void _setupVoiceCommandHandler() {
    _voiceProvider.setCommandCallback((command) {
      switch (command) {
        case 'navigate':
          setState(() {});
          break;

        case 'pick_up':
          setState(() {});
          // Could show confirmation dialog here
          break;

        case 'start_ride':
          setState(() {});
          break;

        case 'end_ride':
          // Show completed screen or return to home
          break;

        case 'call_passenger':
          // Simulate call intent
          _showCallDialog();
          break;

        case 'cancel_ride':
          _showCancelConfirmation();
          break;
      }
    });
  }

  void _showCallDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Call Passenger'),
        content: const Text('Calling Ahmad...'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('CANCEL'),
          ),
        ],
      ),
    );
  }

  void _showCancelConfirmation() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cancel Ride?'),
        content: const Text(
            'Are you sure you want to cancel this ride? This may affect your cancellation rate.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('NO'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('YES'),
          ),
        ],
      ),
    );
  }

  // Method to position voice button at bottom right
  void _positionVoiceButtonBottomRight() {
    if (!mounted) return;
    
    final screenWidth = MediaQuery.of(context).size.width; 
    final screenHeight = MediaQuery.of(context).size.height;
    
    // Position in bottom right with some padding
    setState(() {
      _voiceButtonPosition = Offset(
        screenWidth - 84.0,  // Right edge - button width - some padding
        screenHeight - 180.0  // Bottom edge - button height - some padding
      );
    });
  }
}

class DeviceInfoService {
  final Battery _battery = Battery();
  final Connectivity _connectivity = Connectivity();
  
  // Mock weather data - replace with actual API call in production
  Map<String, String> _weatherCache = {};
  final List<String> _weatherConditions = [
    'Sunny', 'Partly cloudy', 'Cloudy', 'Light rain', 'Raining', 'Thunderstorms'
  ];
  final List<String> _temperatures = ['28°C', '29°C', '30°C', '31°C', '32°C', '27°C'];
Future<Map<String, dynamic>> getDeviceContext() async {
  // Get battery level
  final batteryLevel = await _battery.batteryLevel;
  
  // Get battery charging state
  final batteryState = await _battery.batteryState;
  final isCharging = batteryState == BatteryState.charging || 
                     batteryState == BatteryState.full;
  
  // Get network status
  final connectivityResult = await _connectivity.checkConnectivity();
  final networkStatus = _getNetworkStrength(connectivityResult);

  // Get current time
  final now = DateTime.now();
  final timeStr = DateFormat('h:mm a').format(now);

  // Get traffic condition based on time
  final trafficCondition = _getTrafficCondition(now);
  
  // Get weather data
  final weather = await _getWeatherData();

  return {
    'battery': '$batteryLevel%${isCharging ? " (Charging)" : ""}',
    'network': networkStatus,
    'time': '$timeStr, $trafficCondition traffic',
    'weather': weather,
  };
}

  Future<String> _getWeatherData() async {
    // In a real app, you would call a weather API here
    // For now, we'll use mock data that changes based on time of day
    
    // Check if we have cached weather within the last hour
    final now = DateTime.now();
    final dateKey = '${now.year}-${now.month}-${now.day}-${now.hour}';
    
    if (_weatherCache.containsKey(dateKey)) {
      return _weatherCache[dateKey]!;
    }
    
    // Generate weather based on time of day
    final random = Random();
    int index;
    
    if (now.hour >= 6 && now.hour < 11) {
      // Morning - more likely to be clear
      index = random.nextInt(3); // First 3 conditions
    } else if (now.hour >= 11 && now.hour < 15) {
      // Midday - could be anything
      index = random.nextInt(_weatherConditions.length);
    } else if (now.hour >= 15 && now.hour < 19) {
      // Afternoon - more likely to rain
      index = 2 + random.nextInt(4); // Last 4 conditions
    } else {
      // Evening/night
      index = random.nextInt(_weatherConditions.length);
    }
    
    final tempIndex = random.nextInt(_temperatures.length);
    final weather = "${_weatherConditions[index]}, ${_temperatures[tempIndex]}";
    
    // Cache the result
    _weatherCache[dateKey] = weather;
    
    return weather;
  }

  String _getNetworkStrength(ConnectivityResult result) {
    // Existing method implementation
    switch (result) {
      case ConnectivityResult.mobile:
        return 'Strong (4G)';
      case ConnectivityResult.wifi:
        return 'Strong (WiFi)';
      case ConnectivityResult.none:
        return 'No Connection';
      default:
        return 'Unknown';
    }
  }

  String _getTrafficCondition(DateTime time) {
    // Existing method implementation
    final hour = time.hour;
    if ((hour >= 7 && hour <= 9) || (hour >= 17 && hour <= 19)) {
      return 'heavy';
    } else if ((hour >= 10 && hour <= 16) || (hour >= 20 && hour <= 22)) {
      return 'moderate';
    } else {
      return 'light';
    }
  }
}