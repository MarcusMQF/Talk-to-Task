import 'package:google_generative_ai/google_generative_ai.dart';
import '../api_keys.dart';

class GeminiService {
  late final GenerativeModel _model;
  late final ChatSession? _chat;

  GeminiService() {
    _model = GenerativeModel(
      model: 'gemini-pro',
      apiKey: ApiKeys.geminiApiKey,
      generationConfig: GenerationConfig(
        temperature: 0.7,
        topP: 0.8,
        topK: 40,
      ),
    );
  }

  /// Starts a new chat session
  Future<void> startNewChat() async {
    _chat = _model.startChat();
  }

  /// Sends a message to Gemini and gets a response
  Future<String> sendMessage(String message) async {
    try {
      if (_chat == null) {
        await startNewChat();
      }

      final response = await _chat!.sendMessage(Content.text(message));
      final responseText = response.text;
      
      if (responseText == null) {
        throw Exception('No response from Gemini');
      }
      
      return responseText;
    } catch (e) {
      throw Exception('Failed to get response from Gemini: $e');
    }
  }

  /// Generates a response without maintaining chat history
  Future<String> generateOneTimeResponse(String prompt) async {
    try {
      final response = await _model.generateContent([Content.text(prompt)]);
      final responseText = response.text;
      
      if (responseText == null) {
        throw Exception('No response from Gemini');
      }
      
      return responseText;
    } catch (e) {
      throw Exception('Failed to generate response: $e');
    }
  }
} 