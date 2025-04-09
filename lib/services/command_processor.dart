import '../models/voice_command.dart';

class CommandProcessor {
  static final CommandProcessor _instance = CommandProcessor._internal();
  factory CommandProcessor() => _instance;
  
  CommandProcessor._internal();
  
  // Process text to identify command
  String processCommand(String text) {
    if (text.isEmpty) return 'unknown';
    
    // Convert to lowercase for easier matching
    final lowerText = text.toLowerCase();
    
    // Try to find exact matches in the predefined commands
    for (final cmd in VoiceCommands.commands) {
      // Check if the text contains any trigger phrases
      for (final trigger in cmd.triggers) {
        if (lowerText.contains(trigger)) {
          return cmd.command;
        }
      }
      
      // Check if the text is similar to any examples
      for (final example in cmd.examples) {
        if (_calculateSimilarity(lowerText, example.toLowerCase()) > 0.7) {
          return cmd.command;
        }
      }
    }
    
    // Check for intent based on key phrases
    if (_containsAny(lowerText, ['accept', 'take', 'confirm', 'ok', 'yes', 'sure'])) {
      return 'accept_ride';
    }
    
    if (_containsAny(lowerText, ['reject', 'decline', 'no', 'cancel', 'skip'])) {
      return 'decline_ride';
    }
    
    if (_containsAny(lowerText, ['navigate', 'direction', 'map', 'go to'])) {
      return 'navigate';
    }
    
    if (_containsAny(lowerText, ['call', 'phone', 'dial', 'contact'])) {
      return 'call_passenger';
    }
    
    if (_containsAny(lowerText, ['arrive', 'here', 'reached', 'at location'])) {
      return 'mark_arrived';
    }
    
    if (_containsAny(lowerText, ['start', 'begin', 'picked up', 'commence'])) {
      return 'start_trip';
    }
    
    if (_containsAny(lowerText, ['end', 'complete', 'finish', 'drop off', 'stop'])) {
      return 'end_trip';
    }
    
    if (_containsAny(lowerText, ['problem', 'issue', 'wrong', 'help', 'report'])) {
      return 'report_issue';
    }
    
    if (_containsAny(lowerText, ['offline', 'break', 'pause', 'rest'])) {
      return 'go_offline';
    }
    
    if (_containsAny(lowerText, ['online', 'active', 'available', 'resume'])) {
      return 'go_online';
    }
    
    if (_containsAny(lowerText, ['earning', 'income', 'money', 'profit', 'made'])) {
      return 'check_earnings';
    }
    
    // No command matched
    return 'unknown';
  }
  
  // Check if text contains any of the phrases
  bool _containsAny(String text, List<String> phrases) {
    for (final phrase in phrases) {
      if (text.contains(phrase)) {
        return true;
      }
    }
    return false;
  }
  
  // Calculate similarity between two strings (simplified Levenshtein distance ratio)
  double _calculateSimilarity(String s1, String s2) {
    if (s1.isEmpty || s2.isEmpty) return 0.0;
    
    // Quick check for exact match
    if (s1 == s2) return 1.0;
    
    // Quick check for substring
    if (s1.contains(s2) || s2.contains(s1)) {
      return 0.8; // High similarity for substring matches
    }
    
    // Check for word overlap
    final words1 = s1.split(' ');
    final words2 = s2.split(' ');
    
    int matchedWords = 0;
    for (final word in words1) {
      if (word.length <= 2) continue; // Skip small words
      if (words2.contains(word)) {
        matchedWords++;
      }
    }
    
    // Calculate similarity based on the percentage of matched words
    final similarityRatio = matchedWords / words1.length;
    return similarityRatio;
  }
  
  // Generate response for a given command
  String generateResponse(String command) {
    switch (command) {
      case 'accept_ride':
        return 'Accepting ride. Please wait...';
      case 'decline_ride':
        return 'Declining this ride request.';
      case 'navigate':
        return 'Starting navigation to the destination.';
      case 'call_passenger':
        return 'Calling the passenger now.';
      case 'check_earnings':
        return 'Your earnings today are 150 Ringgit.';
      case 'mark_arrived':
        return 'Marking that you have arrived at the pickup location.';
      case 'start_trip':
        return 'Starting the trip. Have a safe journey.';
      case 'end_trip':
        return 'Ending the trip. Thank you for using Grab.';
      case 'report_issue':
        return 'I\'ll help you report an issue. What seems to be the problem?';
      case 'go_offline':
        return 'Going offline. You will not receive any more ride requests.';
      case 'go_online':
        return 'Going online. You are now available to receive ride requests.';
      default:
        return 'I\'m sorry, I didn\'t understand that command. Please try again.';
    }
  }
} 