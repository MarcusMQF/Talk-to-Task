import 'dart:async';
import 'package:flutter/material.dart';
import 'package:porcupine_flutter/porcupine_manager.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

class WakeWordService {
  static PorcupineManager? _porcupineManager;
  static bool _isListening = false;
  static bool _isInitialized = false;
  
  // Callback to be executed when wake word is detected
  static VoidCallback? onWakeWordDetected;
  
  // Picovoice API key - loaded from .env file
  static String get _apiKey => dotenv.env['PICOVOICE_API_KEY'] ?? '';
  
  // Path to your custom keyword file (stored in assets)
  static const String _customKeywordAssetPath = "assets/hey_grab.ppn";
  static String? _customKeywordFilePath;

  static void _logDebug(String message) {
    debugPrint('🎙️ Wake Word Service: $message');
  }

  static Future<bool> initialize() async {
    if (_isInitialized) {
      _logDebug('Already initialized');
      return true;
    }
    
    try {
      // Request microphone permission
      if (!await _requestPermissions()) {
        _logDebug('Microphone permission not granted');
        return false;
      }
      
      _logDebug('Initializing...');
      
      // Extract the wake word model file from assets to a temp file
      await _extractAssetToFile();
      if (_customKeywordFilePath == null) {
        _logDebug('Failed to extract wake word model');
        return false;
      }
      
      _logDebug('Wake Word: Attempting to initialize with key: ${_maskApiKey(_apiKey)}');
      _logDebug('Wake Word: Using model at: $_customKeywordFilePath');
      
      // Create Porcupine Manager with custom keyword file
      _porcupineManager = await PorcupineManager.fromKeywordPaths(
        _apiKey,
        [_customKeywordFilePath!],
        (keywordIndex) {
          _logDebug('✅ WAKE WORD DETECTED! Index: $keywordIndex');
          if (onWakeWordDetected != null) {
            // Execute on main thread to avoid UI issues
            WidgetsBinding.instance.addPostFrameCallback((_) {
              onWakeWordDetected!();
            });
          }
        },
        errorCallback: (error) {
          _logDebug('❌ ERROR: ${error.message}');
        },
      );
      
      _isInitialized = true;
      _logDebug('✅ Wake word service initialized successfully!');
      return true;
    } catch (err) {
      _logDebug('❌ Failed to initialize Porcupine: $err');
      return false;
    }
  }
  
  // Helper method to mask API key for safe logging
  static String _maskApiKey(String key) {
    if (key.length <= 8) return '****';
    return '${key.substring(0, 4)}****${key.substring(key.length - 4)}';
  }
  
  // Extract asset file to a temporary file that can be read by the Porcupine SDK
  static Future<void> _extractAssetToFile() async {
    try {
      _logDebug('Extracting wake word model from assets...');
      
      // Load the model file from assets
      final ByteData data = await rootBundle.load(_customKeywordAssetPath);
      _logDebug('Model loaded from assets: ${data.lengthInBytes} bytes');
      
      // Create a temporary file
      final tempDir = await getTemporaryDirectory();
      final tempFile = File('${tempDir.path}/hey_grab.ppn');
      
      // Write the asset bytes to the temporary file
      await tempFile.writeAsBytes(
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes)
      );
      
      _customKeywordFilePath = tempFile.path;
      _logDebug('Model extracted to: ${tempFile.path}');
    } catch (e) {
      _logDebug('Failed to extract asset to file: $e');
    }
  }
  
  // Restored the permission handling code
  static Future<bool> _requestPermissions() async {
    try {
      _logDebug('Requesting microphone permission');
      final status = await Permission.microphone.request();
      final granted = status.isGranted;
      _logDebug('Microphone permission ${granted ? 'granted' : 'denied'}');
      return granted;
    } catch (e) {
      _logDebug('Error requesting permissions: $e');
      return false;
    }
  }
  
  static Future<bool> startListening() async {
    if (!_isInitialized) {
      _logDebug('Not initialized yet, initializing now...');
      if (!await initialize()) {
        _logDebug('Failed to initialize');
        return false;
      }
    }
    
    try {
      if (!_isListening && _porcupineManager != null) {
        _logDebug('Starting wake word detection...');
        await _porcupineManager!.start();
        _isListening = true;
        _logDebug('Wake word detection started successfully');
      } else if (_isListening) {
        _logDebug('Already listening');
      } else {
        _logDebug('Porcupine manager is null');
        return false;
      }
      return true;
    } catch (e) {
      _logDebug('Failed to start wake word detection: $e');
      return false;
    }
  }
  
  static Future<void> stopListening() async {
    try {
      if (_isListening && _porcupineManager != null) {
        await _porcupineManager!.stop();
        _isListening = false;
        _logDebug('Wake word detection stopped');
      }
    } catch (e) {
      _logDebug('Failed to stop wake word detection: $e');
    }
  }
  
  static Future<void> dispose() async {
    try {
      if (_porcupineManager != null) {
        await stopListening();
        await _porcupineManager!.delete();
        _porcupineManager = null;
        _isInitialized = false;
        _logDebug('Wake word service disposed');
      }
    } catch (e) {
      _logDebug('Error disposing wake word service: $e');
    }
  }
  
  static bool isListening() {
    return _isListening;
  }
  
  static bool isInitialized() {
    return _isInitialized;
  }
}