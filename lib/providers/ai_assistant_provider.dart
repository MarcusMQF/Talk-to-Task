import 'package:flutter/foundation.dart';
import '../services/gemini_service.dart';

class AIAssistantProvider with ChangeNotifier {
  final GeminiService _geminiService = GeminiService();
  String _lastResponse = '';
  bool _isProcessing = false;

  String get lastResponse => _lastResponse;
  bool get isProcessing => _isProcessing;

  /// Process the transcribed text from voice input and get AI response
  Future<String> processVoiceInput(String transcribedText) async {
    try {
      _isProcessing = true;
      notifyListeners();

      // Add context to help Gemini understand it's assisting a driver
      final prompt = '''You are a helpful AI assistant for a ride-hailing driver. 
      Please provide a clear and concise response to help with their request: 
      $transcribedText''';

      _lastResponse = await _geminiService.generateOneTimeResponse(prompt);
      return _lastResponse;
    } finally {
      _isProcessing = false;
      notifyListeners();
    }
  }

  /// Get AI response in chat context
  Future<String> sendChatMessage(String message) async {
    try {
      _isProcessing = true;
      notifyListeners();

      _lastResponse = await _geminiService.sendMessage(message);
      return _lastResponse;
    } finally {
      _isProcessing = false;
      notifyListeners();
    }
  }

  /// Start a new chat session
  Future<void> startNewChat() async {
    await _geminiService.startNewChat();
    _lastResponse = '';
    notifyListeners();
  }
} 