import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

/// Result model for transcription
class TranscriptionResult {
  final String text;
  final String model;
  final String country;
  final double processingTime;

  TranscriptionResult({
    required this.text,
    required this.model,
    required this.country,
    required this.processingTime,
  });

  factory TranscriptionResult.fromJson(Map<String, dynamic> json) {
    // Extract the main text from the response
    String text = '';
    
    // Check if we have fine-tuned model result first
    if (json['fine_tuned_model'] != null && json['fine_tuned_model']['text'] != null) {
      text = json['fine_tuned_model']['text'];
    } 
    // Fall back to base model if needed
    else if (json['base_model'] != null && json['base_model']['text'] != null) {
      text = json['base_model']['text'];
    }
    
    // Make sure text isn't null
    text = text.isNotEmpty ? text : 'No transcription available';
    
    return TranscriptionResult(
      text: text,
      model: json['fine_tuned_model'] != null ? 
        json['fine_tuned_model']['model_name'] ?? 'Unknown' : 
        json['base_model']['model'] ?? 'Unknown',
      country: json['country'] ?? 'Unknown',
      processingTime: double.tryParse(json['processing_time']?.toString().replaceAll(' seconds', '') ?? '0') ?? 0,
    );
  }
}

/// Service to interface with our custom voice recognition backend
class VoiceRecognitionService {
  // API endpoint - should be configurable in production
  final String _baseUrl = 'http://localhost:8000';
  
  /// Transcribe an audio file using our backend
  /// Returns a TranscriptionResult or null if failed
  Future<TranscriptionResult?> transcribeAudio(
    File audioFile, {
    String country = 'Malaysia',
  }) async {
    try {
      // Create multipart request
      final uri = Uri.parse('$_baseUrl/transcribe/');
      final request = http.MultipartRequest('POST', uri);
      
      // Add form fields
      request.fields['country'] = country;
      
      // Add file
      final fileStream = http.ByteStream(audioFile.openRead());
      final fileLength = await audioFile.length();
      
      // Create multipart file
      final multipartFile = http.MultipartFile(
        'file',  // field name expected by the server
        fileStream,
        fileLength,
        filename: 'audio.m4a',
        contentType: MediaType('audio', 'm4a'),
      );
      
      // Add file to request
      request.files.add(multipartFile);
      
      // Send request
      debugPrint('Sending request to $uri');
      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);
      
      // Check response
      if (response.statusCode == 200) {
        final Map<String, dynamic> data = json.decode(response.body);
        debugPrint('Transcription response: ${response.body}');
        return TranscriptionResult.fromJson(data);
      } else {
        debugPrint('API Error: ${response.statusCode} - ${response.body}');
        return null;
      }
    } catch (e) {
      debugPrint('Exception in voice recognition: $e');
      return null;
    }
  }
} 