import 'dart:convert';
import 'package:google_generative_ai/google_generative_ai.dart';
import '../api_keys.dart';
import 'package:http/http.dart' as http;

class GeminiService {
  late final GenerativeModel _model;
  late ChatSession? _chat;
  final String _baseUrl = 'https://bc21-27-125-249-60.ngrok-free.app';

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

  /// Helper method to build ride context portion of the prompt
  String _buildRideContextPrompt() {
    final buffer = StringBuffer('\nACTIVE RIDE REQUEST DETAILS:\n');

    // Add pickup information
    if (_rideContext['pickupLocation'] != null) {
      buffer.write('Pickup: ${_rideContext['pickupLocation']}\n');

      if (_rideContext['pickupDetail'] != null) {
        buffer.write('   Detail: ${_rideContext['pickupDetail']}\n');
      }
    }

    // Add destination information
    if (_rideContext['destination'] != null) {
      buffer.write('Destination: ${_rideContext['destination']}\n');
    }

    // Add distance information - separate driver-to-pickup from pickup-to-destination
    if (_rideContext['driverToPickupDistance'] != null) {
      buffer.write(
          'Distance to pickup: ${_rideContext['driverToPickupDistance']}\n');
    }

    if (_rideContext['pickupToDestinationDistance'] != null) {
      buffer.write(
          'Trip distance (pickup to destination): ${_rideContext['pickupToDestinationDistance']}\n');
    }

    // Add time information - separate pickup ETA from trip duration
    if (_rideContext['estimatedPickupTime'] != null) {
      buffer.write(
          'Est. time to pickup: ${_rideContext['estimatedPickupTime']}\n');
    }

    if (_rideContext['estimatedTripDuration'] != null) {
      buffer.write(
          'Est. trip duration after pickup: ${_rideContext['estimatedTripDuration']}\n');
    }

    // Add fare and payment information
    if (_rideContext['fareAmount'] != null) {
      buffer.write('Fare: ${_rideContext['fareAmount']}');

      if (_rideContext['paymentMethod'] != null) {
        buffer.write(' (${_rideContext['paymentMethod']})\n');
      } else {
        buffer.write('\n');
      }
    }

    return buffer.toString();
  }

  /// MOVED FROM AudioProcessingService: Creates a Gemini prompt with relevant context
  String createGeminiPrompt(String baseText, String fineTunedText,
      Map<String, dynamic> deviceContext, String country) {
    return '''
You are a helpful and friendly voice assistant for Grab drivers in Malaysia. 
Your goal is to provide concise, relevant, and timely information to help drivers complete their tasks safely and efficiently.

        Here's the current context:
 
    * **Driver Status:** ${_isOnline ? "ONLINE - Available for ride requests" : "OFFLINE - Not accepting ride requests"}
    * **Active Order:** ${_hasActiveRequest ? "YES - Driver has a pending ride request" : "NO - No current ride requests"}
    * **Location:** $country  
    * **Battery:** ${deviceContext['battery'] ?? 'Unknown'}  
    * **Network:** ${deviceContext['network'] ?? 'Unknown'}  
    * **Time:** ${deviceContext['time'] ?? 'Unknown'}  
    * **Weather:** ${deviceContext['weather'] ?? 'Unknown'}  
    ${_rideContext.isNotEmpty ? _buildRideContextPrompt() : ''}

Recent Driver Activity:

        * Transcript A (General Model): $baseText
        * Transcript B (Fine-Tuned Model): $fineTunedText

        Instructions:

        1.  Analyze the driver's status, location, device information, and any active ride request details.
        2.  Review the recent driver activity from Transcript A and Transcript B. Prioritize Transcript B (the fine-tuned model) for accuracy and relevance to the Malaysian context.
        3.  Generate a short, natural-sounding response (no more than two sentences) that DIRECTLY ANSWERS THE QUESTION OR REQUEST in Transcript B, unless there is critical ride information that must be communicated first.
        4.  All response should be in English language.
        5.  If you could not understand the Transcript B, then prioritize the Transcript A. If dont understand both, ask driver to rephrase.
        6.  Compare which Transcript is more accurate and make sense, reply on that.

        Response Guidelines:

        * ONLY mention active ride details if the driver specifically asks about the current ride request, OR if the information is critical.
        * If there is an active ride request and the driver asks about it, provide relevant navigation information.
        * If Transcript B contains a clear question or request, respond to it directly.
        * If online with no active request: Suggest areas with high demand or surge pricing if appropriate.
        * If offline: Provide helpful information.
        * Include only the most critical details. Avoid overwhelming the driver.
        * Use a friendly and professional tone, appropriate for a driving context.
        * Consider the time of day and weather conditions to offer relevant tips.
        * If the transcripts are unclear or irrelevant, provide general, helpful information.
        If you could not understand the Transcript B, then prioritize the Transcript A. If dont understand both, ask driver to rephrase.
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
    String? tripDistance, // Keep for backward compatibility
    String? driverToPickupDistance,
    String? pickupToDestinationDistance,
    String? estimatedPickupTime,
    String? estimatedTripDuration,
  }) {
    _isOnline = isOnline;
    // If driver is offline, there can't be any active requests
    _hasActiveRequest = isOnline ? hasActiveRequest : false;

    // Store ride-specific context when available
    if (pickupLocation != null) _rideContext['pickupLocation'] = pickupLocation;
    if (pickupDetail != null) _rideContext['pickupDetail'] = pickupDetail;
    if (destination != null) _rideContext['destination'] = destination;
    if (paymentMethod != null) _rideContext['paymentMethod'] = paymentMethod;
    if (fareAmount != null) _rideContext['fareAmount'] = fareAmount;

    // Store distance information (both legacy and new detailed format)
    if (tripDistance != null) _rideContext['tripDistance'] = tripDistance;
    if (driverToPickupDistance != null)
      _rideContext['driverToPickupDistance'] = driverToPickupDistance;
    if (pickupToDestinationDistance != null)
      _rideContext['pickupToDestinationDistance'] = pickupToDestinationDistance;

    // Store time estimates
    if (estimatedPickupTime != null)
      _rideContext['estimatedPickupTime'] = estimatedPickupTime;
    if (estimatedTripDuration != null)
      _rideContext['estimatedTripDuration'] = estimatedTripDuration;

    // Clear ride context if offline
    if (!isOnline) {
      _rideContext.clear();
    }
  }

  Future<Map<String, dynamic>> evaluateRideRequest(
      Map<String, dynamic> rideDetails) async {
    try {
      // For testing only - return a dummy response to avoid API failure
      return {
        'recommendation': 'accept',
        'action': 'accept',
        'explanation': 'This is a profitable ride with good fare amount.',
        'confidence': 0.85
      };

      /* COMMENTED OUT REAL IMPLEMENTATION - RESTORE WHEN API IS WORKING
    // Make sure to use the correct API endpoint
    final response = await http.post(
      Uri.parse('https://your-backend-url/api/evaluate-ride'),  // Verify this URL is correct
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(rideDetails),
    );

    if (response.statusCode == 200) {
      return jsonDecode(response.body);
    } else {
      print('Failed to evaluate ride: ${response.statusCode}');
      // Return a fallback response instead of throwing an exception
      return {
        'recommendation': 'ask_user',
        'action': 'ask_user',
        'explanation': 'I couldn\'t analyze this ride. Would you like to accept it?'
      };
    }
    */
    } catch (e) {
      print('Error evaluating ride: $e');
      // Return a fallback response
      return {
        'recommendation': 'ask_user',
        'action': 'ask_user',
        'explanation':
            'Unable to evaluate this ride. Would you like to accept it?'
      };
    }
  }

  /// Clears the current ride context
  void clearRideContext() {
    _rideContext.clear();
  }
}
