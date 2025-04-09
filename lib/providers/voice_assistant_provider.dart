import 'package:flutter/material.dart';
import 'dart:async';
import '../services/speech_service.dart';
import 'package:flutter_tts/flutter_tts.dart';

enum VoiceAssistantState {
  idle,
  listening,
  processing,
  speaking,
  error
}

class VoiceAssistantProvider extends ChangeNotifier {
  // State management
  VoiceAssistantState _state = VoiceAssistantState.idle;
  String _lastWords = '';
  String _errorMessage = '';
  String _responseMessage = '';
  
  // Speech services
  final SpeechService _speechService = SpeechService();
  final FlutterTts _tts = FlutterTts();
  
  // Command callback
  Function(String command)? onCommandRecognized;
  
  // Constructor sets up speech service
  VoiceAssistantProvider() {
    _initSpeechService();
    _initTextToSpeech();
  }
  
  // Initialize speech service
  void _initSpeechService() {
    _speechService.onListeningStarted = () {
      _state = VoiceAssistantState.listening;
      notifyListeners();
    };
    
    _speechService.onListeningFinished = () {
      _state = VoiceAssistantState.processing;
      notifyListeners();
    };
    
    _speechService.onRecognized = (text) {
      _lastWords = text;
      _processCommand(text);
      notifyListeners();
    };
    
    _speechService.onError = (error) {
      _state = VoiceAssistantState.error;
      _errorMessage = error;
      notifyListeners();
      
      // Reset after error
      Timer(const Duration(seconds: 3), () {
        if (_state == VoiceAssistantState.error) {
          reset();
        }
      });
    };
  }
  
  // Initialize text-to-speech
  Future<void> _initTextToSpeech() async {
    await _tts.setLanguage('en-US');
    await _tts.setSpeechRate(0.5);
    await _tts.setVolume(1.0);
    await _tts.setPitch(1.0);
    
    _tts.setCompletionHandler(() {
      if (_state == VoiceAssistantState.speaking) {
        _state = VoiceAssistantState.idle;
        notifyListeners();
      }
    });
    
    _tts.setErrorHandler((error) {
      debugPrint('TTS Error: $error');
    });
  }
  
  // Getters
  String get lastWords => _lastWords;
  VoiceAssistantState get state => _state;
  String get errorMessage => _errorMessage;
  String get responseMessage => _responseMessage;
  bool get isListening => _state == VoiceAssistantState.listening;
  
  // Start listening
  Future<void> startListening() async {
    _state = VoiceAssistantState.listening;
    _lastWords = 'Listening...';
    notifyListeners();
    
    await _speechService.startListening();
    
    // Auto transition to processing after 3 seconds for demo purposes
    Timer(const Duration(seconds: 3), () {
      if (_state == VoiceAssistantState.listening) {
        stopListening();
      }
    });
  }
  
  // Stop listening
  Future<void> stopListening() async {
    await _speechService.stopListening();
  }
  
  // Process recognized command
  void _processCommand(String text) {
    // Map for driver command keywords
    final commandMappings = {
      'navigate': ['navigate', 'directions', 'map', 'go to', 'take me'],
      'pick_up': ['pick up', 'arrived', 'i\'m here', 'pickup'],
      'start_ride': ['start ride', 'begin trip', 'start trip', 'passenger inside'],
      'end_ride': ['end ride', 'complete trip', 'finish', 'drop off'],
      'call_passenger': ['call', 'phone', 'contact', 'ring'],
      'cancel_ride': ['cancel', 'abort', 'reject', 'decline'],
      'check_earnings': ['earnings', 'money', 'income', 'pay'],
      'help': ['help', 'support', 'assistance'],
    };
    
    // Normalize text for matching
    final normalizedText = text.toLowerCase();
    
    // Find matching command
    String? matchedCommand;
    for (final entry in commandMappings.entries) {
      for (final keyword in entry.value) {
        if (normalizedText.contains(keyword)) {
          matchedCommand = entry.key;
          break;
        }
      }
      if (matchedCommand != null) break;
    }
    
    // Generate response based on command
    String response = '';
    if (matchedCommand != null) {
      switch (matchedCommand) {
        case 'navigate':
          response = 'Starting navigation to the destination.';
          break;
        case 'pick_up':
          response = 'Confirming passenger pickup.';
          break;
        case 'start_ride':
          response = 'Starting the ride. Drive safely!';
          break;
        case 'end_ride':
          response = 'Ending the ride. Thank you for using Grab.';
          break;
        case 'call_passenger':
          response = 'Calling the passenger now.';
          break;
        case 'cancel_ride':
          response = 'Cancelling this ride request.';
          break;
        case 'check_earnings':
          response = 'Your earnings today are 150 Ringgit.';
          break;
        case 'help':
          response = 'Getting help from Grab support.';
          break;
      }
    } else {
      response = 'Sorry, I didn\'t understand that command.';
      matchedCommand = 'unknown';
    }
    
    _responseMessage = response;
    _state = VoiceAssistantState.speaking;
    notifyListeners();
    
    // Speak the response
    _speakResponse(response);
    
    // Notify callback if set
    if (onCommandRecognized != null && matchedCommand != 'unknown') {
      onCommandRecognized!(matchedCommand);
    }
  }
  
  // Speak response using TTS
  Future<void> _speakResponse(String text) async {
    if (text.isEmpty) return;
    
    try {
      await _tts.speak(text);
    } catch (e) {
      debugPrint('Error speaking: $e');
      
      // Fallback to timer if TTS fails
      Timer(const Duration(seconds: 3), () {
        if (_state == VoiceAssistantState.speaking) {
          _state = VoiceAssistantState.idle;
          notifyListeners();
        }
      });
    }
  }
  
  // Simulate command recognition for UI demo
  Future<void> simulateCommand(String command) async {
    if (_state != VoiceAssistantState.idle) return;
    
    _state = VoiceAssistantState.listening;
    notifyListeners();
    
    await Future.delayed(const Duration(milliseconds: 500));
    
    _state = VoiceAssistantState.processing;
    _lastWords = command;
    notifyListeners();
    
    await Future.delayed(const Duration(milliseconds: 800));
    
    _processCommand(command);
  }
  
  // Set command callback
  void setCommandCallback(Function(String command) callback) {
    onCommandRecognized = callback;
  }
  
  // Remove command callback
  void removeCommandCallback() {
    onCommandRecognized = null;
  }
  
  // Reset state
  void reset() {
    // Stop speaking if active
    if (_state == VoiceAssistantState.speaking) {
      _tts.stop();
    }
    
    _state = VoiceAssistantState.idle;
    _errorMessage = '';
    _lastWords = '';
    _responseMessage = '';
    notifyListeners();
  }
  
  @override
  void dispose() {
    _speechService.dispose();
    _tts.stop();
    super.dispose();
  }
} 