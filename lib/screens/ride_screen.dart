import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'dart:async';
import 'package:flutter/physics.dart';
import '../constants/app_theme.dart';
import '../constants/map_styles.dart';
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
import '../services/gemini_service.dart';
import '../services/wake_word.dart';
import '../services/get_device_info.dart';
import '../services/weather_service.dart';
import '../widgets/animated_weather_indicator.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'dart:typed_data';
import 'package:flutter_tts/flutter_tts.dart';
import 'dart:math';
import 'package:flutter_dotenv/flutter_dotenv.dart';

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
  Offset _voiceButtonPosition = const Offset(
      300, 600); // Will be adjusted in initState based on screen size

  bool _isOnline = false;
  bool _hasActiveRequest = false;
  bool _isProcessing = false;
  int _remainingSeconds = 15;
  Timer? _requestTimer;
  final FlutterTts _flutterTts = FlutterTts();
  bool _isSpeaking = false;
  // Google Maps controller
  GoogleMapController? _mapController;
  bool _mapInitialized = false; // Track if map has been initially centered

  // Initial camera position (example coordinates - should be replaced with actual pickup location)
  static const LatLng _initialPosition =
      LatLng(3.1390, 101.6869); // KL coordinates

  // Markers for pickup and dropoff locations
  final Set<Marker> _markers = {};
  Marker? _driverLocationMarker;
  Marker? _pickupLocationMarker;
  Set<Polyline> _polylines = {};

  // Timer animations
  late AnimationController _timerShakeController;
  late AnimationController _timerGlowController;
  late Animation<double> _timerShakeAnimation;
  late Animation<double> _timerGlowAnimation;

  // Weather related properties
  final WeatherService _weatherService = WeatherService();
  bool _isLoadingWeather = false;
  Map<String, dynamic>? _weatherData;
  Timer? _weatherUpdateTimer;

  // Store provider reference for safe disposal
  late VoiceAssistantProvider _voiceProvider;

  // Voice Recognition Module
  // CHANGE YOUR LOCAL IPV4 ADDRESS HERE!!
  static const String SERVER_URL = 'http://10.167.65.61:8000/transcribe/';
  static const String DENOISE_URL = 'http://10.167.65.61:8000/denoise/';

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
  final String _customerName = "Marcus Mah";
  String _tripDistance = "3.2 km";
  String _estimatedPickupTime = "8 min";
  String _estimatedTripDuration = "18 min";
  String _driverToPickupDistance = "0.0 km";
  final StreamController<String> _geminiStreamController =
      StreamController<String>.broadcast();

  // Navigation & directions related properties
  bool _isDirectionsLoading = false;
  bool _isNavigationMode = false;
  bool _isNavigatingToPickup = false;
  bool _isNavigatingToDestination = false;
  bool _hasPickedUpPassenger = false;
  int _currentNavigationStep = 0;
  List<Map<String, dynamic>> _navigationSteps = [];
  Timer? _navigationUpdateTimer;

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

    // Set up location updates
    _setupLocationUpdates();
    
    // Set up weather updates
    _setupWeatherUpdates();

    // Position voice button in bottom right after layout is complete
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _positionVoiceButtonBottomRight();
      _setupVoiceCommandHandler();
      
      // Listen to theme changes and update map style accordingly
      final themeProvider = Provider.of<ThemeProvider>(context, listen: false);
      themeProvider.addListener(_updateMapStyleBasedOnTheme);
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
    _voiceProvider.removeCommandCallback();
    
    // Remove theme change listener
    final themeProvider = Provider.of<ThemeProvider>(context, listen: false);
    themeProvider.removeListener(_updateMapStyleBasedOnTheme);
    
    // Dispose of other resources
    _slideController.dispose();
    _requestCardController.dispose();
    _voiceButtonAnimController.dispose();
    _timerShakeController.dispose();
    _timerGlowController.dispose();
    
    _requestTimer?.cancel();
    _amplitudeTimer?.cancel();
    _silenceTimer?.cancel();
    _flutterTts.stop();
    _weatherUpdateTimer?.cancel();
    _navigationUpdateTimer?.cancel();
    _geminiStreamController.close();
    
    _mapController?.dispose();
    super.dispose();
  }
  
  // Fetch weather data for current location
  Future<void> _fetchWeatherData() async {
    if (_currentPosition == null) {
      print('Cannot fetch weather: Current position is null');
      return;
    }
    
    print('Fetching weather for location: ${_currentPosition!.latitude}, ${_currentPosition!.longitude}');
    
    setState(() {
      _isLoadingWeather = true;
    });
    
    try {
      final weatherData = await _weatherService.getWeatherByLocation(
        _currentPosition!.latitude!,
        _currentPosition!.longitude!
      );
      
      setState(() {
        _weatherData = weatherData;
        _isLoadingWeather = false;
      });
      
      print('Weather fetched: ${weatherData['main']} - ${weatherData['emoji']} - ${weatherData['temperature']}°C');
    } catch (e) {
      setState(() {
        _isLoadingWeather = false;
      });
      print('Error fetching weather: $e');
    }
  }
  
  // Setup periodic weather updates
  void _setupWeatherUpdates() {
    // Initial fetch
    _fetchWeatherData();
    
    // Update weather every 15 minutes
    _weatherUpdateTimer = Timer.periodic(const Duration(minutes: 15), (_) {
      _fetchWeatherData();
    });
  }

  Future<void> _initializeWakeWordDetection() async {
    try {
      print('Initializing wake word detection...');

      // Set up callback for wake word detection - only set it once
      WakeWordService.onWakeWordDetected = () {
        print("🎙️ WAKE WORD DETECTED!");
        if (mounted) {
          // Use a microtask to avoid calling setState during build
          Future.microtask(() {
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

      // Start listening for wake words
      bool initialized = await WakeWordService.initialize();
      if (initialized) {
        bool success = await WakeWordService.startListening();
        print('Wake word detection started: $success');

        if (!success) {
          print('Failed to start wake word detection');
        }
      } else {
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
    // Get theme mode first
    // ignore: unused_local_variable
    final isDarkMode = Provider.of<ThemeProvider>(context, listen: false).isDarkMode;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isDismissible: true,
      enableDrag: true,
      isScrollControlled: true, // Allow more height control
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(20),
        ),
      ),
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
    // Only add initial markers if needed
    // Driver location marker will be added from getCurrentLocation
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
    _updateDistanceInformation();
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
        Map<String, dynamic> deviceContext =
            await _getDeviceContextWithWeather();
        print(deviceContext);

        // Create Gemini prompt with dynamic device info
        final prompt = '''
        You are a helpful and friendly voice assistant for Grab drivers in Malaysia. Your goal is to provide concise, relevant, and timely information to help drivers complete their tasks safely and efficiently.

        Here's the current context:

        * **Driver Status:** The driver is currently ${_isOnline ? "ONLINE and available for rides" : "OFFLINE and not accepting ride requests"}.
        * **Active Request:** ${_hasActiveRequest ? "The driver HAS an active ride request." : "The driver has NO active ride request."}
        * **Location:** 
            * Country: ${_country}
            * Coordinates: ${_currentPosition != null ? "${_currentPosition!.latitude}, ${_currentPosition!.longitude}" : "Unknown"}
        * **Device:**
            * Battery Level: ${deviceContext['battery']}
            * Network Connectivity: ${deviceContext['network']}
            * Time: ${deviceContext['time']}
            * Weather: ${deviceContext['weather']}

        ${_hasActiveRequest ? """
        Here are the details of the current ride request:

        * Pickup Location: $_pickupLocation ($_pickupDetail)
        * Destination: $_destination
        * Payment Method: $_paymentMethod
        * Fare Amount: $_fareAmount
        * Trip Distance: $_tripDistance
        * Estimated Pickup Time: $_estimatedPickupTime
        * Estimated Trip Duration: $_estimatedTripDuration
        """ : ""}

        Recent Driver Activity:

        * Transcript A (General Model): $baseText
        * Transcript B (Fine-Tuned Model): $fineTunedText

        Instructions:

        1.  Analyze the driver's status, location, device information, and any active ride request details.
        2.  Review the recent driver activity from Transcript A and Transcript B. Prioritize Transcript B (the fine-tuned model) for accuracy and relevance to the Malaysian context.
        3.  Generate a short, natural-sounding response (no more than two sentences) that DIRECTLY ANSWERS THE QUESTION OR REQUEST in Transcript B, unless there is critical ride information that must be communicated first.
        4.  All response should be in English language.
        5.  If you could not understand the Transcript B, then prioritize the Transcript A. If dont understand both, ask driver to rephrase.
        6.  Compare which Transcript is more accurate and possible and reply on that,

        Response Guidelines:

        * FIRST PRIORITY: If Transcript B contains a clear question or request, respond to it directly.
        * SECOND PRIORITY: If there is an active ride request, provide essential navigation information.
        * If online with no active request: Suggest areas with high demand or surge pricing.
        * If offline: Provide helpful information.
        * Include only the most critical details. Avoid overwhelming the driver.
        * Use a friendly and professional tone, appropriate for a driving context.
        * Consider the time of day and weather conditions to offer relevant tips.
        * If the transcripts are unclear or irrelevant, provide general, helpful information.
        * When asked about high-demand areas, use the exact coordinates provided in the Location section to give precise, location-specific answers, but no need to mention the coordinates.

        Relevant high-demand locations in Kuala Lumpur:
        * KLCC/Bukit Bintang area (3.1478° N, 101.7155° E): High demand from tourists and business travelers, especially evenings and weekends.
        * KL Sentral (3.1344° N, 101.6866° E): Transportation hub with high demand during morning/evening rush hours.
        * Bangsar/Mid Valley (3.1182° N, 101.6765° E): Popular shopping and dining areas with peak demand on weekends.
        * Damansara Heights (3.1508° N, 101.6551° E): Business district with high demand during weekday mornings/evenings.
        * Petaling Jaya/Sunway (3.0733° N, 101.6073° E): Busy area with high demand near Sunway Pyramid mall.
        * Mont Kiara (3.1711° N, 101.6492° E): Expat area with consistent demand, especially mornings and evenings.

        Examples:
        1. If Transcript B shows "Di manakah kawasan permintaan tertinggi sekarang?" (Where is the area with highest demand now?), respond with information about high demand areas near the driver's current coordinates, even if there's an active ride. If coordinates are unknown, ask the driver to share their location.
        2. If Transcript B shows a navigation question but there's an active ride, prioritize the active ride details unless the question is specifically about a different location.

        Output:
        A brief, natural-sounding response for the Grab driver.
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
    await _location.changeSettings(
      accuracy: LocationAccuracy
          .high, // Use high accuracy instead of PRIORITY_HIGH_ACCURACY
      interval: 10000, // Update interval in milliseconds
      distanceFilter: 5, // Minimum distance in meters to trigger updates
    );
    try {
      _currentPosition = await _location.getLocation();
      print(
          'Current position: ${_currentPosition?.latitude}, ${_currentPosition?.longitude}');

      // Try to get the country name
      if (_currentPosition != null) {
        try {
          final placemarks = await geocoding.placemarkFromCoordinates(
            _currentPosition!.latitude!,
            _currentPosition!.longitude!,
          );

          if (placemarks.isNotEmpty) {
            setState(() {
              _country = placemarks.first.country ?? "Unknown";
              print('Country detected: $_country');
            });
          }
        } catch (e) {
          print('Error getting country: $e');
        }
      }
    } catch (e) {
      print('Error getting location: $e');
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

          // Update driver's current location marker
          _updateDriverLocationMarker();

          // Only center on first load when map is initialized,
          // but don't move the camera on subsequent location updates
          if (_mapController != null &&
              !_mapInitialized &&
              _currentPosition != null) {
            _mapInitialized = true;
            final driverPosition = LatLng(
                _currentPosition!.latitude!, _currentPosition!.longitude!);

            _mapController!.animateCamera(
              CameraUpdate.newLatLng(driverPosition),
            );
          }
        });
      }
    } catch (e) {
      print('Error getting current location: $e');
    }
  }

  // Update this method to handle post-pickup navigation differently
  void _updateDriverLocationMarker() {
    if (_currentPosition != null) {
      final driverPosition =
          LatLng(_currentPosition!.latitude!, _currentPosition!.longitude!);

      // In normal mode or pickup mode, update the driver marker with current position
      if (!_isNavigatingToDestination) {
        // Create or update the driver marker with green pin at current location
        final updatedMarker = Marker(
          markerId: const MarkerId('driver_location'),
          position: driverPosition,
          icon:
              BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
          infoWindow: const InfoWindow(title: 'Your Location'),
          zIndex: 2, // Ensure driver marker is on top of other markers
        );

        setState(() {
          // Remove old driver marker if it exists
          if (_driverLocationMarker != null) {
            _markers.remove(_driverLocationMarker);
          }

          // Add new driver marker
          _driverLocationMarker = updatedMarker;
          _markers.add(_driverLocationMarker!);

          // If we're navigating to pickup location
          if (_isNavigatingToPickup) {
            // Make sure pickup marker is visible
            if (_pickupLocationMarker != null &&
                !_markers.contains(_pickupLocationMarker)) {
              _markers.add(_pickupLocationMarker!);
            }

            // Update route from current position to pickup if needed
            // Only update if driver has moved significantly
            if (_polylines.isNotEmpty &&
                _calculateDistance(
                        driverPosition, _polylines.first.points.first) >
                    0.05) {
              _polylines.clear();
              final pickupPosition = _pickupLocationMarker != null
                  ? _pickupLocationMarker!.position
                  : LatLng(3.0733, 101.6073);
              _createRouteLinePoints(driverPosition, pickupPosition,
                  AppTheme.grabGreen, 'route_to_pickup');
            }
          }
        });
      }
      // When navigating to destination, we don't update anything
      // This preserves the route from pickup to destination
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
    // Don't show online toggle when in navigation mode
    if (_isNavigationMode) return const SizedBox.shrink();

    // Get theme provider to check dark mode status
    final isDarkMode = Provider.of<ThemeProvider>(context).isDarkMode;

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
            color: isDarkMode ? const Color(0xFF252525) : Colors.white,
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
                                ? (isDarkMode ? Colors.grey[500] : Colors.grey[400])
                                : (isDarkMode ? Colors.grey[700] : Colors.grey[300]),
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
                            color: _isOnline
                                ? (isDarkMode ? Colors.grey[500] : Colors.grey[400])
                                : (isDarkMode ? Colors.grey[700] : Colors.grey[300]),
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
                                      isDarkMode ? Colors.grey[600]! : Colors.grey[400]!,
                                      isDarkMode ? Colors.grey[600]!.withOpacity(0.8) : Colors.grey[400]!.withOpacity(0.8)
                                    ],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            borderRadius: BorderRadius.circular(20),
                            boxShadow: [
                              BoxShadow(
                                color: (_isOnline
                                        ? AppTheme.grabGreen
                                        : isDarkMode ? Colors.grey[600]! : Colors.grey[400]!)
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
                                      : isDarkMode ? Colors.white : const Color.fromARGB(255, 126, 125, 125),
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

    // Get theme provider to check dark mode status
    final themeProvider = Provider.of<ThemeProvider>(context);
    final isDarkMode = themeProvider.isDarkMode;

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
          color: isDarkMode ? const Color(0xFF252525) : Colors.white,
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
                    ? (isDarkMode ? Colors.red.withOpacity(0.2) : Colors.red.withOpacity(0.1))
                    : (isDarkMode ? AppTheme.grabGreen.withOpacity(0.2) : AppTheme.grabGreen.withOpacity(0.1)),
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
                            isDarkMode ? Colors.grey.shade800 : const Color.fromARGB(255, 255, 255, 255),
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
                      // Customer name with profile icon
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: AppTheme.grabGreen.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.person_rounded,
                              color: AppTheme.grabGreen,
                              size: 16,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              _customerName,
                              style: const TextStyle(
                                color: AppTheme.grabGreen,
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Spacer(),
                      // Payment method
                      Row(
                        children: [
                          Icon(Icons.payment,
                              size: 16, color: isDarkMode ? Colors.grey.shade300 : Colors.grey.shade700),
                          const SizedBox(width: 4),
                          Text(
                            _paymentMethod,
                            style: TextStyle(
                              color: isDarkMode ? Colors.grey.shade300 : Colors.grey.shade700,
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
                          // Trip distance
                          Text(
                            'Trip distance: $_tripDistance',
                            style: TextStyle(
                              color: isDarkMode ? Colors.grey.shade400 : Colors.grey.shade600,
                              fontWeight: FontWeight.w500,
                              fontSize: 12,
                            ),
                          ),
                          // To pickup distance moved here
                          Text(
                            'To pickup: $_driverToPickupDistance',
                            style: TextStyle(
                              color: Colors.grey.shade600,
                              fontWeight: FontWeight.w500,
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
                                'ETA to Pickup: $_estimatedPickupTime',
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
                  Builder(
                    builder: (context) {
                      final isDarkMode = Provider.of<ThemeProvider>(context).isDarkMode;
                      return Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: isDarkMode ? const Color(0xFF333333) : Colors.grey.shade100,
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
                      );
                    }
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
                        Expanded(
                          child: Builder(
                            builder: (context) {
                              final isDarkMode = Provider.of<ThemeProvider>(context).isDarkMode;
                              return Column(
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
                                          color: isDarkMode ? Colors.grey.shade300 : Colors.grey,
                                          fontSize: 12,
                                        ),
                                      ),
                                      Text(
                                        'Sunway Pyramid Mall, PJ',
                                        style: TextStyle(
                                          color: isDarkMode ? Colors.white : AppTheme.grabBlack,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                      Text(
                                        'Main entrance, near Starbucks',
                                        style: TextStyle(
                                          color: isDarkMode ? Colors.grey.shade400 : Colors.grey,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ],
                                  ),

                                  const SizedBox(height: 35),

                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Destination',
                                        style: TextStyle(
                                          color: isDarkMode ? Colors.grey.shade300 : Colors.grey,
                                          fontSize: 12,
                                        ),
                                      ),
                                      Text(
                                        'KL Sentral, Kuala Lumpur',
                                        style: TextStyle(
                                          color: isDarkMode ? Colors.white : AppTheme.grabBlack,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              );
                            }
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
                            backgroundColor: isDarkMode ? const Color(0xFF333333) : Colors.white,
                            foregroundColor: isDarkMode ? Colors.grey.shade300 : AppTheme.grabGrayDark,
                            elevation: 0,
                            side: BorderSide(color: isDarkMode ? Colors.grey.shade700 : Colors.grey.shade300),
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          child: Text(
                            'Decline',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: isDarkMode ? Colors.grey.shade300 : AppTheme.grabGrayDark,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      // Accept button
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () {
                            _acceptRideRequest();
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
    final themeProvider = Provider.of<ThemeProvider>(context);
    final isDarkMode = themeProvider.isDarkMode;
    
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isDarkMode ? const Color(0xFF353535) : Colors.white,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.15),
                    blurRadius: 8,
                    spreadRadius: 1,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: Icon(icon, color: AppTheme.grabGreen, size: 22),
            ),
            const SizedBox(height: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: isDarkMode ? Colors.grey.shade300 : Colors.grey.shade700,
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
      top: 145,
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
                onTap: _moveToCurrentLocation,
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

  // Build weather indicator positioned on the left side
  Widget _buildWeatherIndicator() {
    final isDarkMode = Provider.of<ThemeProvider>(context).isDarkMode;
    
    return Positioned(
      left: 21,
      top: 140,
      child: _isLoadingWeather
          ? Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.blue, // Blue background regardless of theme
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 4,
                    spreadRadius: 1,
                  ),
                ],
              ),
              child: SizedBox(
                width: 15,
                height: 15,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              ),
            )
          : _weatherData == null
              ? const SizedBox.shrink()
              : AnimatedWeatherIndicator(
                  weatherEmoji: _weatherData!['emoji'],
                  weatherCondition: _weatherData!['main'],
                  isDarkMode: isDarkMode,
                  backgroundColor: Colors.blue, // Pass blue background color
                ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<ThemeProvider>(
      builder: (context, themeProvider, _) {
        // Apply map style if map controller is already created
        if (_mapController != null) {
          _mapController!.setMapStyle(themeProvider.isDarkMode ? MapStyles.dark : MapStyles.light);
        }
        
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
                  
                  // Apply theme-based map style
                  controller.setMapStyle(themeProvider.isDarkMode ? MapStyles.dark : MapStyles.light);
                },
                markers: _markers,
                polylines: _polylines,
                myLocationEnabled: true,
                myLocationButtonEnabled: false,
                zoomControlsEnabled: false,
                mapToolbarEnabled: false,
                compassEnabled: true,
              ),
              _buildOnlineToggle(),
              // Weather indicator
              _buildWeatherIndicator(),
              // Country flag indicator - hide during navigation mode
              if (!_isNavigationMode)
                Positioned(
                  top: 55,
                  left: 20,
                  child: GestureDetector(
                    onTap: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Location: $_country')),
                      );
                    },
                    child: Container(
                      width: 39,
                      height: 39,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(20),
                        color: themeProvider.isDarkMode ? const Color(0xFF2A2A2A) : Colors.white,
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
              if (_isOnline && !_isNavigationMode) _buildRequestCard(),
              if (_isNavigationMode) _buildNavigationInterface(),
              _buildMapControls(),
              _buildDraggableVoiceButton(),

              // Add loading indicator when directions are being fetched
              if (_isDirectionsLoading)
                Container(
                  color: Colors.black.withOpacity(0.3),
                  child: const Center(
                    child: CircularProgressIndicator(
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  ),
                ),

              // AI Chat button positioned at top right
              Positioned(
                top: 300,
                right: 16,
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: AppTheme.grabGreen,
                    borderRadius: BorderRadius.circular(8),
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
                      borderRadius: BorderRadius.circular(11),
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (context) => const AIChatScreen()),
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
      },
    );
  }

  // MIC BUTTON
  Widget _buildDraggableVoiceButton() {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final isDarkMode = themeProvider.isDarkMode;
    
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
            color: isDarkMode ? const Color(0xFF2A2A2A) : Colors.white,
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
                // Get theme mode first
                // ignore: unused_local_variable
                final isDarkMode = Provider.of<ThemeProvider>(context, listen: false).isDarkMode;
                showModalBottomSheet(
                  context: context,
                  backgroundColor: Colors.transparent,
                  isDismissible: true,
                  enableDrag: true,
                  isScrollControlled: true, // Allow more height control
                  shape: const RoundedRectangleBorder(
                    borderRadius: BorderRadius.vertical(
                      top: Radius.circular(20),
                    ),
                  ),
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
              child: Center(
                child: Icon(
                  Icons.mic,
                  color: isDarkMode ? Colors.white : AppTheme.grabGreen,
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
    // Get theme provider to check dark mode status
    final isDarkMode = Provider.of<ThemeProvider>(context, listen: false).isDarkMode;
    
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
              decoration: BoxDecoration(
                color: isDarkMode ? const Color(0xFF252525) : Colors.white,
                borderRadius: const BorderRadius.vertical(
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
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w500,
                            color: isDarkMode ? Colors.grey.shade300 : Colors.grey.shade700,
                          ),
                        ),
                      ],
                    )
                  else if (_isProcessing)
                    Column(
                      children: [
                        const CircularProgressIndicator(
                          valueColor:
                              AlwaysStoppedAnimation<Color>(AppTheme.grabGreen),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          "Processing...",
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w500,
                            color: isDarkMode ? Colors.grey.shade300 : Colors.grey.shade700,
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
                              Text(
                                "Your speech:",
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                  color: isDarkMode ? Colors.grey.shade400 : Colors.grey.shade700,
                                ),
                              ),
                              Text(
                                _baseTranscription,
                                style: TextStyle(
                                  fontSize: 14,
                                  color: isDarkMode ? Colors.grey.shade400 : Colors.grey.shade700,
                                  fontStyle: FontStyle.italic,
                                ),
                              ),
                              const SizedBox(height: 12),
                            ],
                            if (_fineTunedTranscription.isNotEmpty &&
                                _fineTunedTranscription !=
                                    _baseTranscription) ...[
                              Text(
                                "Enhanced recognition:",
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                  color: isDarkMode ? Colors.grey.shade400 : Colors.grey.shade700,
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
                              style: TextStyle(
                                fontSize: 16,
                                color: isDarkMode ? Colors.grey.shade300 : Colors.grey.shade700,
                                height: 1.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                  else
                    Text(
                      "No data available",
                      style: TextStyle(
                        fontSize: 16,
                        color: isDarkMode ? Colors.grey.shade300 : Colors.grey.shade700,
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
    // Get theme mode
    final isDarkMode = Provider.of<ThemeProvider>(context, listen: false).isDarkMode;
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: isDarkMode ? const Color(0xFF252525) : Colors.white,
        title: Text('Cancel Trip?', 
          style: TextStyle(
            color: isDarkMode ? Colors.white : Colors.black,
          ),
        ),
        content: Text(
          'Are you sure you want to cancel this trip? This will end the current navigation.',
          style: TextStyle(
            color: isDarkMode ? Colors.grey.shade300 : Colors.black87,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('NO', style: TextStyle(color: isDarkMode ? Colors.grey.shade300 : Colors.grey.shade700)),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _cancelTrip(); // Use _cancelTrip instead of _endTrip
            },
            child: Text('YES', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  // Method to cancel the trip and exit navigation mode
  void _cancelTrip() {
    // Speak confirmation of cancellation
    _speakResponse("Trip cancelled.");
    
    setState(() {
      _isNavigationMode = false;
      _isNavigatingToPickup = false;
      _isNavigatingToDestination = false;
      _hasPickedUpPassenger = false;
      _navigationSteps.clear();
      _currentNavigationStep = 0;

      // Clear navigation route
      _polylines.clear();

      // Reset markers except for driver location
      _markers.clear();
      if (_driverLocationMarker != null) {
        _markers.add(_driverLocationMarker!);
      }
    });

    // Focus back on device's current location
    if (_mapController != null && _currentPosition != null) {
      final driverPosition =
          LatLng(_currentPosition!.latitude!, _currentPosition!.longitude!);

      // Animate camera to focus on driver's current location with appropriate zoom level
      _mapController!.animateCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(
            target: driverPosition,
            zoom: 15, // Standard zoom level for city navigation
          ),
        ),
      );
    }

    // Show cancellation message
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Trip cancelled'),
        duration: Duration(seconds: 2),
        backgroundColor: Colors.red,
      ),
    );
    
    // Make driver available for new passenger requests
    if (_isOnline) {
      // Show a brief message to indicate the driver is available for new orders
      Future.delayed(const Duration(seconds: 3), () {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Ready for new passenger'),
              duration: Duration(seconds: 2),
              backgroundColor: AppTheme.grabGreen,
            ),
          );
        }
      });
      
      // Show a new order request after a short delay
      Future.delayed(const Duration(seconds: 5), () {
        if (mounted && _isOnline) {
          _showNewRequest();
        }
      });
    }
  }

  // Method to position voice button at bottom right
  void _positionVoiceButtonBottomRight() {
    if (!mounted) return;

    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;

    // Position in bottom right with some padding
    setState(() {
      _voiceButtonPosition = Offset(
          screenWidth - 84.0, // Right edge - button width - some padding
          screenHeight - 180.0 // Bottom edge - button height - some padding
          );
    });
  }

  // Add this new method to set up periodic location updates
  void _setupLocationUpdates() {
    // Variables to track significant location change
    double lastLat = 0;
    double lastLng = 0;
    bool isFirstUpdate = true;
    
    // Set up location change listener
    _location.onLocationChanged.listen((LocationData currentLocation) {
      if (mounted) {
        setState(() {
          _currentPosition = currentLocation;
        });
        
        // Check if location has changed significantly (more than 500 meters)
        // or if it's the first update
        final currentLat = currentLocation.latitude!;
        final currentLng = currentLocation.longitude!;
        
        if (isFirstUpdate || 
            calculateDistance(lastLat, lastLng, currentLat, currentLng) > 0.5) {
          // Update last position
          lastLat = currentLat;
          lastLng = currentLng;
          isFirstUpdate = false;
          
          // Fetch weather for new location
          _fetchWeatherData();
        }

        // Update driver marker on the map if in navigation mode
        if (_isNavigationMode && _mapController != null) {
          _updateDriverLocationMarker();

          // Calculate distance to pickup if navigating to pickup
          if (_isNavigatingToPickup && _pickupLocationMarker != null) {
            // Calculate distance between driver and pickup point
            final driverLat = _currentPosition!.latitude!;
            final driverLng = _currentPosition!.longitude!;
            final pickupLat = _pickupLocationMarker!.position.latitude;
            final pickupLng = _pickupLocationMarker!.position.longitude;

            // Simple distance calculation (not taking into account roads)
            final distance =
                calculateDistance(driverLat, driverLng, pickupLat, pickupLng);

            setState(() {
              _driverToPickupDistance = "${distance.toStringAsFixed(1)} km";

              // If driver is very close to pickup point, show pickup confirmation
              if (distance < 0.1 && !_hasPickedUpPassenger) {
                // Within 100 meters
                _showPickupConfirmation();
              }
            });
          }
        }
      }
    });
  }

// Helper method to calculate distance between two points
  double calculateDistance(double lat1, double lon1, double lat2, double lon2) {
    const double earthRadius = 6371; // Radius of the earth in km
    final double dLat = _degreesToRadians(lat2 - lat1);
    final double dLon = _degreesToRadians(lon2 - lon1);

    final double a = sin(dLat / 2) * sin(dLat / 2) +
        cos(_degreesToRadians(lat1)) *
            cos(_degreesToRadians(lat2)) *
            sin(dLon / 2) *
            sin(dLon / 2);

    final double c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return earthRadius * c; // Distance in km
  }

  double _degreesToRadians(double degrees) {
    return degrees * (pi / 180);
  }

  // Add a method to accept the ride request
  void _acceptRideRequest() {
    if (_hasActiveRequest) {
      setState(() {
        _hasActiveRequest = false;
        _requestTimer?.cancel();
        _isNavigationMode = true;
        _isNavigatingToPickup = true;
        _isNavigatingToDestination = false;
        _hasPickedUpPassenger = false;
        _currentNavigationStep = 0;
      });

      // Speak confirmation of accepting the order
      _speakResponse(
          "Order accepted. Starting navigation to pickup location at ${_pickupLocation}.");

      // Get pickup and destination coordinates for routing
      if (_currentPosition != null) {
        final driverPosition =
            LatLng(_currentPosition!.latitude!, _currentPosition!.longitude!);
        final pickupPosition =
            LatLng(3.0733, 101.6073); // Sunway Pyramid coordinates
        final destinationPosition =
            LatLng(3.1348, 101.6867); // KL Sentral coordinates

        // Setup initial route to pickup
        _setupRouteToPickup(
            driverPosition, pickupPosition, destinationPosition);
      }

      // Get accurate pickup and destination coordinates
      // Fetch route details and show on map
      _fetchRideDetails();

      // Generate navigation steps to pickup
      _generateNavigationStepsToPickup();

      // Start navigation updates
      _startNavigationUpdates();
    }
  }

  // Add this method to generate navigation steps to pickup
  void _generateNavigationStepsToPickup() {
    // In a real app, these steps would come from a navigation API
    // For demo purposes, we're creating dummy turn-by-turn directions
    _navigationSteps = [
      {
        'instruction': 'Head north on current street',
        'distance': '300m',
        'maneuver': 'straight',
        'icon': Icons.arrow_upward,
      },
      {
        'instruction': 'Turn right onto Jalan Bukit Bintang',
        'distance': '450m',
        'maneuver': 'right',
        'icon': Icons.turn_right,
      },
      {
        'instruction': 'Keep left at the fork',
        'distance': '200m',
        'maneuver': 'fork-left',
        'icon': Icons.fork_left,
      },
      {
        'instruction': 'Turn left onto Jalan Sultan Ismail',
        'distance': '600m',
        'maneuver': 'left',
        'icon': Icons.turn_left,
      },
      {
        'instruction': 'Continue straight for 2km',
        'distance': '2km',
        'maneuver': 'straight',
        'icon': Icons.arrow_upward,
      },
      {
        'instruction': 'Destination will be on your right',
        'distance': '50m',
        'maneuver': 'destination',
        'icon': Icons.place,
      },
    ];
  }

  // Add this method to generate navigation steps to destination
  void _generateNavigationStepsToDestination() {
    // In a real app, these steps would come from a navigation API
    // For demo purposes, we're creating dummy turn-by-turn directions
    _navigationSteps = [
      {
        'instruction': 'Exit the pickup area and head east',
        'distance': '150m',
        'maneuver': 'straight',
        'icon': Icons.arrow_upward,
      },
      {
        'instruction': 'Turn right onto Federal Highway',
        'distance': '1.2km',
        'maneuver': 'right',
        'icon': Icons.turn_right,
      },
      {
        'instruction': 'Keep in the left lane',
        'distance': '800m',
        'maneuver': 'lane-left',
        'icon': Icons.arrow_left,
      },
      {
        'instruction': 'Take the exit toward KL Sentral',
        'distance': '400m',
        'maneuver': 'exit',
        'icon': Icons.exit_to_app,
      },
      {
        'instruction': 'Turn left onto Jalan Stesen Sentral',
        'distance': '350m',
        'maneuver': 'left',
        'icon': Icons.turn_left,
      },
      {
        'instruction': 'You have arrived at KL Sentral',
        'distance': '0m',
        'maneuver': 'destination',
        'icon': Icons.place,
      },
    ];
  }

  // Method to start navigation updates
  void _startNavigationUpdates() {
    // Cancel any existing timer
    _navigationUpdateTimer?.cancel();

    // Reset the current step
    _currentNavigationStep = 0;

    // Speak the first instruction immediately
    if (_navigationSteps.isNotEmpty) {
      _speakNavigationInstruction(_navigationSteps[0]);
    }

    // Create a timer that advances to the next navigation step every few seconds
    // In a real app, this would be based on GPS position updates
    _navigationUpdateTimer =
        Timer.periodic(const Duration(seconds: 10), (timer) {
      if (mounted) {
        setState(() {
          if (_currentNavigationStep < _navigationSteps.length - 1) {
            _currentNavigationStep++;

            // Speak the new navigation instruction
            _speakNavigationInstruction(
                _navigationSteps[_currentNavigationStep]);
          } else {
            // Last step reached
            if (_isNavigatingToPickup) {
              // Speak arrival at pickup notification
              _speakResponse(
                  "You have arrived at the pickup location. Please look for your passenger.");

              // Show pickup confirmation UI
              _showPickupConfirmation();
              timer.cancel();
            } else if (_isNavigatingToDestination) {
              // Speak arrival at destination notification
              _speakResponse(
                  "You have arrived at your destination. This trip is now complete.");

              // Trip completed
              _showTripCompletedDialog();
              timer.cancel();
            }
          }
        });
      } else {
        timer.cancel();
      }
    });
  }

  // Method to show pickup confirmation UI
  void _showPickupConfirmation() {
    if (!mounted) return;

    // Cancel any existing navigation updates
    _navigationUpdateTimer?.cancel();

    setState(() {
      _isNavigatingToPickup = false;
    });

    // Get theme mode
    final isDarkMode = Provider.of<ThemeProvider>(context, listen: false).isDarkMode;

    // Show a bottom sheet for pickup confirmation
    showModalBottomSheet(
      context: context,
      isDismissible: false,
      enableDrag: false,
      backgroundColor: Colors.transparent,
      builder: (BuildContext context) {
        return Container(
          decoration: BoxDecoration(
            color: isDarkMode ? const Color(0xFF252525) : Colors.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
          ),
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'You have arrived at the pickup location',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: isDarkMode ? Colors.white : Colors.black,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Please confirm when you have picked up the passenger',
                style: TextStyle(
                  color: isDarkMode ? Colors.grey.shade400 : Colors.grey,
                ),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  // Call passenger button
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _showCallDialog,
                      icon: const Icon(Icons.call, color: AppTheme.grabGreen),
                      label: const Text('Call'),
                      style: ElevatedButton.styleFrom(
                        foregroundColor: AppTheme.grabGreen,
                        backgroundColor: isDarkMode ? const Color(0xFF333333) : Colors.white,
                        side: const BorderSide(color: AppTheme.grabGreen),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Pickup confirmation button
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () {
                        Navigator.pop(context);
                        _confirmPickup();
                      },
                      icon: const Icon(Icons.check_circle, color: Colors.white),
                      label: const Text('Picked Up'),
                      style: ElevatedButton.styleFrom(
                        foregroundColor: Colors.white,
                        backgroundColor: AppTheme.grabGreen,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              // Cancel trip button
              TextButton.icon(
                onPressed: () {
                  Navigator.pop(context);
                  _cancelTrip();
                },
                icon: const Icon(Icons.cancel, color: Colors.red),
                label: const Text(
                  'Cancel Trip',
                  style: TextStyle(color: Colors.red),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // Method to confirm pickup and start navigation to destination
  void _confirmPickup() {
    // Store pickup location coordinates
    final LatLng pickupPosition = _pickupLocationMarker != null
        ? _pickupLocationMarker!.position
        : LatLng(3.0733, 101.6073); // Fallback to Sunway Pyramid coordinates

    // For destination we use the actual destination coordinates
    final destinationPosition =
        LatLng(3.1348, 101.6867); // KL Sentral coordinates

    setState(() {
      _hasPickedUpPassenger = true;
      _isNavigatingToPickup = false;
      _isNavigatingToDestination = true;

      // Generate navigation steps to destination
      _generateNavigationStepsToDestination();

      // Clear all existing markers and routes
      _markers.clear();
      _polylines.clear();

      // Add pickup location marker (green)
      _driverLocationMarker = Marker(
        markerId: const MarkerId('driver_location'),
        position: pickupPosition, // Position at pickup location
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
        infoWindow: InfoWindow(title: 'Pickup: $_pickupLocation'),
        zIndex: 2,
      );

      // Add destination marker (red)
      final destinationMarker = Marker(
        markerId: const MarkerId('destination'),
        position: destinationPosition,
        // Use red for destination
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
        infoWindow: InfoWindow(title: 'Destination: $_destination'),
      );

      // Add only pickup and destination markers
      _markers.add(_driverLocationMarker!);
      _markers.add(destinationMarker);
    });

    // Speak confirmation of pickup and start of navigation to destination
    _speakResponse(
        "Passenger picked up. Starting navigation to ${_destination}.");

    // Setup route from pickup to destination only
    _createRouteLinePoints(pickupPosition, destinationPosition,
        AppTheme.grabGreen, 'route_to_destination');

    // Fit both markers on the map
    _fitMarkersOnMap([pickupPosition, destinationPosition]);

    // Fetch updated route details for destination
    _fetchRideDetails();

    // Start navigation updates for destination
    _startNavigationUpdates();
  }

  // Method to show trip completed dialog
  void _showTripCompletedDialog() {
    if (!mounted) return;

    // Get theme mode
    final isDarkMode = Provider.of<ThemeProvider>(context, listen: false).isDarkMode;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        backgroundColor: isDarkMode ? const Color(0xFF252525) : Colors.white,
        title: Text('Trip Completed', 
          style: TextStyle(
            color: isDarkMode ? Colors.white : Colors.black,
          ),
        ),
        content: Text(
          'You have arrived at the destination. Would you like to end the trip?',
          style: TextStyle(
            color: isDarkMode ? Colors.grey.shade300 : Colors.black87,
          ),
        ),
        actions: [
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _endTrip();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.grabGreen,
              foregroundColor: Colors.white,
            ),
            child: const Text('End Trip'),
          ),
        ],
      ),
    );
  }

  // Method to end the trip and return to normal mode
  void _endTrip() {
    setState(() {
      _isNavigationMode = false;
      _isNavigatingToPickup = false;
      _isNavigatingToDestination = false;
      _hasPickedUpPassenger = false;
      _navigationSteps.clear();
      _currentNavigationStep = 0;

      // Clear navigation route
      _polylines.clear();

      // Reset markers except for driver location
      _markers.clear();
      if (_driverLocationMarker != null) {
        _markers.add(_driverLocationMarker!);
      }
    });

    // Focus back on device's current location
    if (_mapController != null && _currentPosition != null) {
      final driverPosition =
          LatLng(_currentPosition!.latitude!, _currentPosition!.longitude!);

      // Animate camera to focus on driver's current location with appropriate zoom level
      _mapController!.animateCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(
            target: driverPosition,
            zoom: 15, // Standard zoom level for city navigation
          ),
        ),
      );
    }

    // Show a brief message to indicate the driver is available for new orders
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Ready for new passenger'),
        duration: Duration(seconds: 2),
        backgroundColor: AppTheme.grabGreen,
      ),
    );

    // Show a new order request after a short delay if online
    if (_isOnline) {
      Future.delayed(const Duration(seconds: 3), () {
        if (mounted && _isOnline) {
          _showNewRequest();
        }
      });
    }
  }

  // Fetch accurate ride details from API
  Future<void> _fetchRideDetails() async {
    setState(() {
      _isDirectionsLoading = true;
    });

    try {
      if (_currentPosition == null) {
        setState(() {
          _isDirectionsLoading = false;
        });
        return;
      }

      // Driver's current position
      final LatLng driverPosition =
          LatLng(_currentPosition!.latitude!, _currentPosition!.longitude!);

      // These would normally come from your backend API with real coordinates
      final LatLng pickupPosition =
          LatLng(3.0733, 101.6073); // Actual Sunway Pyramid Mall coordinates
      final LatLng destinationPosition =
          LatLng(3.1348, 101.6867); // Actual KL Sentral coordinates

      // Calculate distances using the Haversine formula
      final double driverToPickupDistance =
          _calculateDistance(driverPosition, pickupPosition);
      final double pickupToDestinationDistance =
          _calculateDistance(pickupPosition, destinationPosition);

      // Update the UI with accurate information
      setState(() {
        _driverToPickupDistance =
            "${driverToPickupDistance.toStringAsFixed(1)} km";
        _tripDistance = "${pickupToDestinationDistance.toStringAsFixed(1)} km";

        // Estimate pickup time based on average speed of 40 km/h
        final int pickupMinutes = (driverToPickupDistance / 40 * 60).round();
        _estimatedPickupTime = "$pickupMinutes min";

        // Estimate trip duration based on average speed of 35 km/h (accounting for traffic)
        final int tripMinutes = (pickupToDestinationDistance / 35 * 60).round();
        _estimatedTripDuration = "$tripMinutes min";

        _isDirectionsLoading = false;
      });

      // Only show route on map if we're not already in destination navigation mode
      // This prevents redrawing the route after pickup
      if (!(_isNavigatingToDestination && _hasPickedUpPassenger)) {
        // Show route on map - using different methods based on phase
        if (_isNavigatingToPickup) {
          // During pickup phase, we can use the specialized method for pickup route
          _showRouteToPickup();
        } else if (!_isNavigationMode) {
          // For full route display with all markers, but only if not in navigation mode
          _setupRouteDisplay(
              driverPosition, pickupPosition, destinationPosition);
        }
      }
    } catch (e) {
      setState(() {
        _isDirectionsLoading = false;
      });
      print('Error fetching ride details: $e');
    }
  }

  // Add this method to draw the route between driver and pickup location
  Future<void> _showRouteToPickup() async {
    if (_currentPosition == null || _pickupLocationMarker == null) return;

    // Get driver and pickup positions
    final driverPosition =
        LatLng(_currentPosition!.latitude!, _currentPosition!.longitude!);

    final pickupPosition = _pickupLocationMarker!.position;

    // Clear existing polylines
    setState(() {
      _polylines.clear();
    });

    // Use the API-based routing method to create the route
    await _createRouteLinePoints(
        driverPosition, pickupPosition, AppTheme.grabGreen, 'route_to_pickup');

    // Adjust camera to show both markers
    _fitBoundsForRoute(driverPosition, pickupPosition);
  }

  // Add a method to adjust the camera to show both markers
  void _fitBoundsForRoute(LatLng origin, LatLng destination) {
    if (_mapController == null) return;

    // Calculate the bounds that include both points with some padding
    final double minLat = min(origin.latitude, destination.latitude) - 0.01;
    final double maxLat = max(origin.latitude, destination.latitude) + 0.01;
    final double minLng = min(origin.longitude, destination.longitude) - 0.01;
    final double maxLng = max(origin.longitude, destination.longitude) + 0.01;

    final bounds = LatLngBounds(
      southwest: LatLng(minLat, minLng),
      northeast: LatLng(maxLat, maxLng),
    );

    // Animate camera to fit these bounds
    _mapController!.animateCamera(CameraUpdate.newLatLngBounds(bounds, 50));
  }

  // Calculate distance between two coordinates in kilometers
  double _calculateDistance(LatLng start, LatLng end) {
    const double earthRadius = 6371; // Earth's radius in kilometers

    // Convert latitudes and longitudes from degrees to radians
    final double startLatRad = start.latitude * (pi / 180);
    final double startLngRad = start.longitude * (pi / 180);
    final double endLatRad = end.latitude * (pi / 180);
    final double endLngRad = end.longitude * (pi / 180);

    // Haversine formula
    final double dLat = endLatRad - startLatRad;
    final double dLng = endLngRad - startLngRad;

    final double a = sin(dLat / 2) * sin(dLat / 2) +
        cos(startLatRad) * cos(endLatRad) * sin(dLng / 2) * sin(dLng / 2);
    final double c = 2 * atan2(sqrt(a), sqrt(1 - a));
    final double distance = earthRadius * c;

    return distance;
  }

  // Update accurate distance information for the order
  void _updateDistanceInformation() {
    if (_currentPosition != null) {
      // Driver's current position
      final LatLng driverPosition =
          LatLng(_currentPosition!.latitude!, _currentPosition!.longitude!);

      // These would normally come from your backend API with real coordinates
      // Using actual coordinates for Sunway Pyramid Mall and KL Sentral
      final LatLng pickupPosition =
          LatLng(3.0733, 101.6073); // Sunway Pyramid Mall
      final LatLng destinationPosition = LatLng(3.1348, 101.6867); // KL Sentral

      // Calculate distances
      final double driverToPickupDistance =
          _calculateDistance(driverPosition, pickupPosition);
      final double pickupToDestinationDistance =
          _calculateDistance(pickupPosition, destinationPosition);

      // Format distances with one decimal place
      setState(() {
        _driverToPickupDistance =
            "${driverToPickupDistance.toStringAsFixed(1)} km";
        _tripDistance = "${pickupToDestinationDistance.toStringAsFixed(1)} km";

        // Estimate pickup time - rough estimate based on average speed of 40 km/h
        final int pickupMinutes = (driverToPickupDistance / 40 * 60).round();
        _estimatedPickupTime = "$pickupMinutes min";

        // Estimate trip duration - rough estimate based on average speed of 35 km/h (accounting for traffic)
        final int tripMinutes = (pickupToDestinationDistance / 35 * 60).round();
        _estimatedTripDuration = "$tripMinutes min";
      });
    }
  }

  // Set up route display on map with markers and polyline
  void _setupRouteDisplay(LatLng driverPosition, LatLng pickupPosition,
      LatLng destinationPosition) {
    // Clear existing markers and polylines
    _markers.clear();
    _polylines.clear();

    // Add driver's current location marker
    _driverLocationMarker = Marker(
      markerId: const MarkerId('driver_location'),
      position: driverPosition,
      icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
      infoWindow: const InfoWindow(title: 'Your Location'),
      zIndex: 2, // Ensure driver marker is on top of other markers
    );

    // Add pickup location marker
    _pickupLocationMarker = Marker(
      markerId: const MarkerId('pickup_location'),
      position: pickupPosition,
      icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
      infoWindow: InfoWindow(title: 'Pickup: $_pickupLocation'),
    );

    // Add destination marker
    Marker destinationMarker = Marker(
      markerId: const MarkerId('destination'),
      position: destinationPosition,
      icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
      infoWindow: InfoWindow(title: 'Destination: $_destination'),
    );

    // Add all markers to the map
    _markers.add(_driverLocationMarker!);
    _markers.add(_pickupLocationMarker!);
    _markers.add(destinationMarker);

    // Create route polylines for driver to pickup and pickup to destination using API-based routing
    _createRouteLinePoints(
        driverPosition, pickupPosition, AppTheme.grabGreen, 'route_to_pickup');
    _createRouteLinePoints(pickupPosition, destinationPosition,
        AppTheme.grabGreen, 'route_to_destination');

    // Fit all markers on the map
    _fitAllMarkersOnMap();
  }

  // Fit all markers on the map
  void _fitAllMarkersOnMap() {
    if (_mapController == null || _markers.isEmpty) return;

    // Calculate the bounds that include all markers
    double minLat = 90;
    double maxLat = -90;
    double minLng = 180;
    double maxLng = -180;

    for (final marker in _markers) {
      if (marker.position.latitude < minLat) minLat = marker.position.latitude;
      if (marker.position.latitude > maxLat) maxLat = marker.position.latitude;
      if (marker.position.longitude < minLng)
        minLng = marker.position.longitude;
      if (marker.position.longitude > maxLng)
        maxLng = marker.position.longitude;
    }

    // Add some padding
    minLat -= 0.02;
    maxLat += 0.02;
    minLng -= 0.02;
    maxLng += 0.02;

    final bounds = LatLngBounds(
      southwest: LatLng(minLat, minLng),
      northeast: LatLng(maxLat, maxLng),
    );

    // Animate camera to fit all markers
    _mapController!.animateCamera(CameraUpdate.newLatLngBounds(bounds, 50));
  }

  // Build the navigation interface for turn-by-turn directions
  Widget _buildNavigationInterface() {
    if (_navigationSteps.isEmpty ||
        _currentNavigationStep >= _navigationSteps.length) {
      return const SizedBox.shrink();
    }
    
    // Get theme provider to check dark mode status
    final themeProvider = Provider.of<ThemeProvider>(context);
    final isDarkMode = themeProvider.isDarkMode;

    final currentStep = _navigationSteps[_currentNavigationStep];

    return Column(
      children: [
        // Show loading indicator when fetching route
        if (_isDirectionsLoading)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 8),
            color: Colors.black.withOpacity(0.7),
            child: const Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      )),
                  SizedBox(width: 12),
                  Text(
                    "Loading route...",
                    style: TextStyle(color: Colors.white, fontSize: 14),
                  ),
                ],
              ),
            ),
          ),
        // Top navigation bar
        Container(
          color: Colors.black.withOpacity(0.8),
          padding: const EdgeInsets.fromLTRB(16, 50, 16, 16),
          child: Column(
            children: [
              // Passenger status indicator
              if (_hasPickedUpPassenger)
                Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.green,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.person, color: Colors.white, size: 14),
                      SizedBox(width: 4),
                      Text(
                        'Passenger on board',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              Row(
                children: [
                  // Exit navigation button
                  GestureDetector(
                    onTap: () {
                      // Get theme mode
                      final isDarkMode = Provider.of<ThemeProvider>(context, listen: false).isDarkMode;
                      
                      showDialog(
                        context: context,
                        builder: (context) => AlertDialog(
                          backgroundColor: isDarkMode ? const Color(0xFF252525) : Colors.white,
                          title: Text('Cancel Trip?', 
                            style: TextStyle(
                              color: isDarkMode ? Colors.white : Colors.black,
                            ),
                          ),
                          content: Text(
                            'Are you sure you want to cancel this trip? This will end the current navigation.',
                            style: TextStyle(
                              color: isDarkMode ? Colors.grey.shade300 : Colors.black87,
                            ),
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(context),
                              child: Text('NO', style: TextStyle(color: isDarkMode ? Colors.grey.shade300 : Colors.grey.shade700)),
                            ),
                            TextButton(
                              onPressed: () {
                                Navigator.pop(context);
                                _cancelTrip(); // Use _cancelTrip instead of _endTrip
                              },
                              child: Text('YES', style: TextStyle(color: Colors.red)),
                            ),
                          ],
                        ),
                      );
                    },
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Icon(
                        Icons.close,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  // Navigation status
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _isNavigatingToPickup
                              ? 'Navigating to pickup'
                              : 'Navigating to destination',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          _isNavigatingToPickup
                              ? _pickupLocation
                              : _destination,
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  // ETA
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        _isNavigatingToPickup
                            ? _estimatedPickupTime
                            : _estimatedTripDuration,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const Text(
                        'ETA',
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
        const Spacer(),
        // Bottom navigation card
        Container(
          margin: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: isDarkMode ? const Color(0xFF252525) : Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.2),
                blurRadius: 10,
                offset: const Offset(0, -2),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Next maneuver section
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    // Maneuver icon
                    Container(
                      width: 60,
                      height: 60,
                      decoration: BoxDecoration(
                        color: isDarkMode ? AppTheme.grabGreen.withOpacity(0.2) : AppTheme.grabGreen.withOpacity(0.1),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        currentStep['icon'] as IconData,
                        color: AppTheme.grabGreen,
                        size: 30,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Distance to next turn
                        Text(
                          '${currentStep['distance']} km',
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: isDarkMode ? Colors.white : Colors.black87,
                          ),
                        ),
                        const SizedBox(height: 4),
                        // Direction instruction
                        Text(
                          currentStep['instruction'] as String,
                          style: TextStyle(
                            fontSize: 14,
                            color: isDarkMode ? Colors.grey.shade300 : Colors.grey.shade700,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              // Progress indicator
              LinearProgressIndicator(
                value: (_currentNavigationStep + 1) / _navigationSteps.length,
                backgroundColor: isDarkMode ? Colors.grey.shade800 : Colors.grey.shade200,
                valueColor: const AlwaysStoppedAnimation(AppTheme.grabGreen),
              ),
              // Action buttons
              Padding(
                padding: const EdgeInsets.all(16),
                child: _isNavigatingToDestination
                    ? SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: ElevatedButton(
                          onPressed: _showTripCompletedDialog,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.grabGreen,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                            elevation: 2,
                          ),
                          child: const Text(
                            'Arrived',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      )
                    : Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
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
                          if (_isNavigatingToPickup)
                            _buildNavigationAction(
                              icon: Icons.check_circle,
                              label: 'Pickup',
                              onTap: _showPickupConfirmation,
                            )
                          else
                            _buildNavigationAction(
                              icon: Icons.flag,
                              label: 'Arrived',
                              onTap: _showTripCompletedDialog,
                            ),
                        ],
                      ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // Add this method to fetch actual route from Google Maps Directions API
  Future<List<LatLng>> _fetchRouteCoordinates(
      LatLng origin, LatLng destination) async {
    try {
      // Get API key from environment variables using flutter_dotenv
      final apiKey = dotenv.env['GOOGLE_MAPS_API_KEY'] ?? '';

      // Create the request URL for the Directions API
      final String url = 'https://maps.googleapis.com/maps/api/directions/json?'
          'origin=${origin.latitude},${origin.longitude}'
          '&destination=${destination.latitude},${destination.longitude}'
          '&mode=driving'
          '&key=$apiKey';

      // Make the HTTP request to the Directions API
      final response = await http.get(Uri.parse(url));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);

        if (data['status'] == 'OK') {
          // Extract the route points from the response
          final routes = data['routes'] as List;

          if (routes.isNotEmpty) {
            // Get the encoded polyline string from the first route
            final points = routes[0]['overview_polyline']['points'] as String;

            // Decode the polyline string into a list of LatLng points
            return _decodePolyline(points);
          }
        } else {
          print('Directions API error: ${data['status']}');
          throw Exception('Failed to get directions: ${data['status']}');
        }
      } else {
        print('HTTP error: ${response.statusCode}');
        throw Exception('Failed to get directions: ${response.statusCode}');
      }

      // If we reach here without returning or throwing, throw an exception
      throw Exception('Failed to get valid route data');
    } catch (e) {
      print('Error fetching route: $e');
      // Don't provide a fallback, just propagate the error
      throw Exception('Could not fetch route data: $e');
    }
  }

  // Helper method to decode Google's polyline format
  List<LatLng> _decodePolyline(String encoded) {
    List<LatLng> poly = [];
    int index = 0, len = encoded.length;
    int lat = 0, lng = 0;

    while (index < len) {
      int b, shift = 0, result = 0;

      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);

      int dlat = ((result & 1) != 0 ? ~(result >> 1) : (result >> 1));
      lat += dlat;

      shift = 0;
      result = 0;

      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);

      int dlng = ((result & 1) != 0 ? ~(result >> 1) : (result >> 1));
      lng += dlng;

      final p = LatLng(lat / 1E5, lng / 1E5);
      poly.add(p);
    }

    return poly;
  }

  // Update this method to create realistic route polylines using the fetched coordinates
  Future<void> _createRouteLinePoints(
      LatLng start, LatLng end, Color color, String id) async {
    try {
      // Show loading indicator
      setState(() {
        _isDirectionsLoading = true;
      });

      // Fetch route coordinates - this will throw if it fails
      final List<LatLng> routePoints = await _fetchRouteCoordinates(start, end);

      // Only create and add the polyline if we got valid route points
      if (routePoints.isNotEmpty) {
        final polyline = Polyline(
          polylineId: PolylineId(id),
          points: routePoints,
          color: color,
          width: 4,
        );

        setState(() {
          _polylines.add(polyline);
          _isDirectionsLoading = false;
        });
      }
    } catch (e) {
      print('Error creating route: $e');
      // Simply hide the loading indicator but don't add any polyline
      setState(() {
        _isDirectionsLoading = false;
      });

      // Notify the user that route fetching failed
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not load route. Please try again.'),
          duration: Duration(seconds: 3),
        ),
      );
    }
  }

  // Updated method to specifically set up the route to pickup location
  Future<void> _setupRouteToPickup(LatLng driverPosition, LatLng pickupPosition,
      LatLng destinationPosition) async {
    try {
      // Clear existing markers and polylines
      _markers.clear();
      _polylines.clear();

      // Add driver's current location marker
      _driverLocationMarker = Marker(
        markerId: const MarkerId('driver_location'),
        position: driverPosition,
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
        infoWindow: const InfoWindow(title: 'Your Location'),
        zIndex: 2, // Ensure driver marker is on top of other markers
      );

      // Add pickup location marker
      _pickupLocationMarker = Marker(
        markerId: const MarkerId('pickup_location'),
        position: pickupPosition,
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
        infoWindow: InfoWindow(title: 'Pickup: $_pickupLocation'),
      );

      // Add markers to the map - only driver and pickup in pickup phase
      _markers.add(_driverLocationMarker!);
      _markers.add(_pickupLocationMarker!);

      // Draw route from driver to pickup
      await _createRouteLinePoints(driverPosition, pickupPosition,
          AppTheme.grabGreen, 'route_to_pickup');

      // Fit both markers on the map
      _fitMarkersOnMap([driverPosition, pickupPosition]);
    } catch (e) {
      print('Error setting up route to pickup: $e');
    }
  }

  // Helper method to fit map to show specific points
  void _fitMarkersOnMap(List<LatLng> points) {
    if (_mapController == null || points.isEmpty) return;

    // Calculate the bounds that include all points
    double minLat = 90;
    double maxLat = -90;
    double minLng = 180;
    double maxLng = -180;

    for (final point in points) {
      if (point.latitude < minLat) minLat = point.latitude;
      if (point.latitude > maxLat) maxLat = point.latitude;
      if (point.longitude < minLng) minLng = point.longitude;
      if (point.longitude > maxLng) maxLng = point.longitude;
    }

    // Add some padding
    minLat -= 0.02;
    maxLat += 0.02;
    minLng -= 0.02;
    maxLng += 0.02;

    final bounds = LatLngBounds(
      southwest: LatLng(minLat, minLng),
      northeast: LatLng(maxLat, maxLng),
    );

    // Animate camera to fit all points
    _mapController!.animateCamera(CameraUpdate.newLatLngBounds(bounds, 50));
  }

  // Method to speak navigation direction instructions
  Future<void> _speakNavigationInstruction(Map<String, dynamic> step) async {
    if (!mounted) return;

    // Stop any ongoing speech
    if (_isSpeaking) {
      await _flutterTts.stop();
    }

    // Create a natural sounding navigation instruction
    String instruction = step['instruction'] as String;
    String distance = step['distance'] as String;
    String maneuver = step['maneuver'] as String;

    // Format the speech in a more natural way
    String speechText = '';

    // Add appropriate phrases based on maneuver type
    if (maneuver == 'destination') {
      speechText =
          'You have arrived at your ${_isNavigatingToPickup ? 'pickup point' : 'destination'}. $instruction';
    } else if (distance == '0m') {
      speechText = instruction;
    } else {
      speechText = 'In $distance, $instruction';
    }

    // Speak the instruction
    setState(() {
      _isSpeaking = true;
    });

    await _flutterTts.speak(speechText);
  }

  // Updated method to move to current location and update weather
  void _moveToCurrentLocation() {
    if (_mapController != null && _currentPosition != null) {
      // Use driver's actual position from current location
      final driverPosition = LatLng(_currentPosition!.latitude!,
          _currentPosition!.longitude!);

      // If there's an active request/order, move the map view higher
      if (_hasActiveRequest) {
        final adjustedPosition = LatLng(
            driverPosition.latitude -
                0.005, // Move up by 0.005 on the map
            driverPosition.longitude);

        _mapController!.animateCamera(
          CameraUpdate.newCameraPosition(
            CameraPosition(
              target: adjustedPosition,
              zoom:
                  16, // Increased zoom level for better detail with order container
            ),
          ),
        );
      } else {
        // Center on driver's location normally
        _mapController!.animateCamera(
          CameraUpdate.newCameraPosition(
            CameraPosition(
              target: driverPosition,
              zoom: 15,
            ),
          ),
        );
      }
      
      // Update weather data for current location
      _fetchWeatherData();
    }
  }

  void _updateMapStyleBasedOnTheme() {
    final themeProvider = Provider.of<ThemeProvider>(context, listen: false);
    _mapController?.setMapStyle(themeProvider.isDarkMode ? MapStyles.dark : MapStyles.light);
  }

  // Update the method for getting device context
  Future<Map<String, dynamic>> _getDeviceContextWithWeather() async {
    // Get basic device context
    Map<String, dynamic> deviceContext = await _deviceInfo.getDeviceContext();
    
    // Override weather with our local _weatherData if it's available
    if (_weatherData != null) {
      final weatherText = "${_weatherData!['main']}, ${_weatherData!['temperature'].toStringAsFixed(1)}°C ${_weatherData!['emoji']}";
      deviceContext['weather'] = weatherText;
      print('Using local weather data for Gemini: $weatherText');
    } else {
      print('No local weather data available for Gemini, using DeviceInfo weather');
    }
    
    return deviceContext;
  }
}
