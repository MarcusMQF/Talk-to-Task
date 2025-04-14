import 'package:google_generative_ai/google_generative_ai.dart';
import '../api_keys.dart';

class GeminiService {
  late final GenerativeModel _model;
  late ChatSession? _chat;

  GeminiService() {
    _model = GenerativeModel(
      model: 'gemini-1.5-pro',
      apiKey: ApiKeys.geminiApiKey,
      generationConfig: GenerationConfig(
        temperature: 0.7,
        topP: 0.8,
        topK: 40,
        maxOutputTokens: 1024,
      ),
    );
  }

  /// Starts a new chat session
  Future<void> startNewChat() async {
    _chat = _model.startChat( 
      history: [
        Content.text("You are an AI driving assistant for a ride-hailing app. "
            "Help the driver with their tasks, answer questions, and provide useful information. "
            "Keep responses short and helpful for someone who is driving. "
            "Current date: ${DateTime.now().toString().split(' ')[0]}"),
      ],
    );
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