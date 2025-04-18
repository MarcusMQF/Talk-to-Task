import 'package:google_generative_ai/google_generative_ai.dart';
import '../api_keys.dart';

class GeminiService {
  late final GenerativeModel _model;
  late ChatSession? _chat;
  
  // Added context variables for prompts
  bool _isOnline = true;
  bool _hasActiveRequest = false;
  Map<String, String?> _rideContext = {};

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
  
  /// MOVED FROM AudioProcessingService: Creates a Gemini prompt with relevant context
  String createGeminiPrompt(String baseText, String fineTunedText,
      Map<String, dynamic> deviceContext, String country) {
    
    return '''
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
    - Location: $country  
    - Battery: ${deviceContext['battery'] ?? 'Unknown'}  
    - Network: ${deviceContext['network'] ?? 'Unknown'}  
    - Time: ${deviceContext['time'] ?? 'Unknown'}  
    - Weather: ${deviceContext['weather'] ?? 'Unknown'}  
    ${_rideContext.isNotEmpty ? _buildRideContextPrompt() : ''}

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

  /// MOVED FROM AudioProcessingService: Updates the Gemini prompt context
  void updatePromptContext({
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
  }) {
    _isOnline = isOnline;
    _hasActiveRequest = hasActiveRequest;
    
    // Store ride-specific context when available
    if (pickupLocation != null) _rideContext['pickupLocation'] = pickupLocation;
    if (pickupDetail != null) _rideContext['pickupDetail'] = pickupDetail;
    if (destination != null) _rideContext['destination'] = destination;
    if (paymentMethod != null) _rideContext['paymentMethod'] = paymentMethod;
    if (fareAmount != null) _rideContext['fareAmount'] = fareAmount;
    if (tripDistance != null) _rideContext['tripDistance'] = tripDistance;
    if (estimatedPickupTime != null) _rideContext['estimatedPickupTime'] = estimatedPickupTime;
    if (estimatedTripDuration != null) _rideContext['estimatedTripDuration'] = estimatedTripDuration;
  }
  
  /// Helper method to build ride context portion of the prompt
  String _buildRideContextPrompt() {
    final buffer = StringBuffer('\nActive Ride Details:\n');
    
    if (_rideContext['pickupLocation'] != null) {
      buffer.write('- Pickup: ${_rideContext['pickupLocation']}\n');
      
      if (_rideContext['pickupDetail'] != null) {
        buffer.write('  (${_rideContext['pickupDetail']})\n');
      }
    }
    
    if (_rideContext['destination'] != null) {
      buffer.write('- Destination: ${_rideContext['destination']}\n');
    }
    
    if (_rideContext['fareAmount'] != null) {
      buffer.write('- Fare: ${_rideContext['fareAmount']}');
      
      if (_rideContext['paymentMethod'] != null) {
        buffer.write(' (${_rideContext['paymentMethod']})\n');
      } else {
        buffer.write('\n');
      }
    }
    
    if (_rideContext['tripDistance'] != null) {
      buffer.write('- Trip distance: ${_rideContext['tripDistance']}\n');
    }
    
    if (_rideContext['estimatedPickupTime'] != null) {
      buffer.write('- Est. pickup time: ${_rideContext['estimatedPickupTime']}\n');
    }
    
    if (_rideContext['estimatedTripDuration'] != null) {
      buffer.write('- Est. trip duration: ${_rideContext['estimatedTripDuration']}\n');
    }
    
    return buffer.toString();
  }
  
  /// Clears the current ride context
  void clearRideContext() {
    _rideContext.clear();
  }
}