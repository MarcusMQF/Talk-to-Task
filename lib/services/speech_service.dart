import 'package:flutter/foundation.dart';
import 'dart:async';

// Speech service state options
enum SpeechServiceState {
  notInitialized,
  initializing,
  initialized,
  listening,
  processing,
  speaking,
  error,
  idle
}

/// Mock speech service for UI demonstration
/// In a real app, this would interface with speech recognition APIs
class SpeechService {
  static final SpeechService _instance = SpeechService._internal();
  factory SpeechService() => _instance;
  
  SpeechService._internal();
  
  // State tracking
  SpeechServiceState _state = SpeechServiceState.initialized;
  String _lastRecognizedWords = '';
  String _errorMessage = '';
  
  // Callbacks
  VoidCallback? onListeningStarted;
  VoidCallback? onListeningFinished;
  Function(String text)? onRecognized;
  Function(SpeechServiceState state)? onStateChanged;
  Function(String error)? onError;
  
  // Getters
  SpeechServiceState get state => _state;
  String get lastRecognizedWords => _lastRecognizedWords;
  String get errorMessage => _errorMessage;
  bool get isListening => _state == SpeechServiceState.listening;
  
  // Mock start listening function
  Future<bool> startListening() async {
    _setState(SpeechServiceState.listening);
    
    if (onListeningStarted != null) {
      onListeningStarted!();
    }
    
    // Auto-stop after 3 seconds for demo
    Timer(const Duration(seconds: 3), () {
      if (_state == SpeechServiceState.listening) {
        stopListening();
      }
    });
    
    return true;
  }
  
  // Mock stop listening
  Future<void> stopListening() async {
    _setState(SpeechServiceState.processing);
    
    if (onListeningFinished != null) {
      onListeningFinished!();
    }
    
    // Simulate processing and recognition
    Timer(const Duration(milliseconds: 800), () {
      _simulateRecognition();
    });
  }
  
  // Simulate speech recognition
  Future<void> _simulateRecognition() async {
    // Sample phrases that might be recognized
    final phrases = [
      'Accept this ride',
      'Navigate to the destination',
      'Call the passenger',
      'End the trip',
      'Check my earnings',
    ];
    
    // Randomly select a phrase based on current second
    final index = DateTime.now().second % phrases.length;
    final recognizedText = phrases[index];
    
    _lastRecognizedWords = recognizedText;
    
    if (onRecognized != null) {
      onRecognized!(recognizedText);
    }
    
    _setState(SpeechServiceState.idle);
  }
  
  // Mock speak text function
  Future<void> speak(String text) async {
    _setState(SpeechServiceState.speaking);
    
    // Simulate speaking time based on text length
    final speakingTime = (text.length * 80).clamp(800, 3000);
    
    Timer(Duration(milliseconds: speakingTime), () {
      if (_state == SpeechServiceState.speaking) {
        _setState(SpeechServiceState.idle);
      }
    });
  }
  
  // Update state and notify listeners
  void _setState(SpeechServiceState newState) {
    _state = newState;
    
    if (onStateChanged != null) {
      onStateChanged!(newState);
    }
  }
  
  // Cleanup resources - no real resources to clean in mock version
  void dispose() {}
} 