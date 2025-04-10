import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../constants/app_theme.dart';
import '../providers/voice_assistant_provider.dart';
import '../providers/theme_provider.dart';
import '../services/gemini_service.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:just_audio/just_audio.dart';

class AIChatScreen extends StatefulWidget {
  const AIChatScreen({super.key});

  @override
  State<AIChatScreen> createState() => _AIChatScreenState();
}

class _AIChatScreenState extends State<AIChatScreen> {
  final TextEditingController _chatController = TextEditingController();
  final List<Map<String, dynamic>> _messages = [
    {
      'sender': 'ai', 
      'message': 'Hi! Nice to see you. How are you today? Can I help you?',
      'timestamp': DateTime.now().toString(),
    },
  ]; // Initial welcome message

  bool _isSendingMessage = false;
  late VoiceAssistantProvider _voiceProvider;
  final GeminiService _geminiService = GeminiService();
  final AudioPlayer _audioPlayer = AudioPlayer();
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _voiceProvider = Provider.of<VoiceAssistantProvider>(context, listen: false);
    
    // Set up callback to handle recognized text
    _voiceProvider.setCommandCallback((recognizedText) {
      setState(() {
        _chatController.text = recognizedText;
        _sendMessage(recognizedText);
      });
    });
    
    // Initialize Gemini chat session
    _geminiService.startNewChat();
    
    // Speak the initial welcome message
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _speakAIResponse(_messages.first['message']!);
    });
  }

  @override
  void dispose() {
    _voiceProvider.removeCommandCallback();
    _chatController.dispose();
    _audioPlayer.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _sendMessage(String message) async {
    if (message.trim().isEmpty) return;

    setState(() {
      _messages.add({
        'sender': 'user', 
        'message': message,
        'timestamp': DateTime.now().toString(),
      });
      _chatController.clear();
      _isSendingMessage = true;
    });
    
    // Scroll to bottom after adding message
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollToBottom();
    });

    try {
      // Send message to Gemini
      final aiResponse = await _geminiService.sendMessage(message);
      
      // Clean the response text by removing extra newlines
      final cleanedResponse = aiResponse.trim().replaceAll(RegExp(r'\n{2,}'), '\n');
      
      setState(() {
        _messages.add({
          'sender': 'ai', 
          'message': cleanedResponse,
          'timestamp': DateTime.now().toString(),
        });
        _isSendingMessage = false;
      });
      
      // Scroll to bottom after receiving response
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollToBottom();
      });
      
      // Use TTS to speak the response
      _speakAIResponse(cleanedResponse);
      
    } catch (e) {
      setState(() {
        _messages.add({
          'sender': 'ai', 
          'message': 'Sorry, I encountered an error processing your request.',
          'timestamp': DateTime.now().toString(),
        });
        _isSendingMessage = false;
      });
      print('Error sending message: $e');
      
      // Scroll to bottom after error message
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollToBottom();
      });
    }
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  Future<void> _speakAIResponse(String text) async {
    // Reset any ongoing speech
    _voiceProvider.reset();
    
    // Use the TTS API directly
    await _sendTextToTTS(text);
  }
  
  Future<void> _sendTextToTTS(String text) async {
    // Use actual IP address of your computer when running on a physical device
    final apiUrl = Uri.parse('http://10.167.68.40:5000/tts');
    
    print('Attempting to connect to TTS API at: $apiUrl');

    try {
      print('Sending TTS request for: "${text.length > 40 ? text.substring(0, 40) + "..." : text}"');
      
      final response = await http.post(
        apiUrl,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'text': text}),
      );

      if (response.statusCode == 200) {
        print('TTS request successful');
        
        try {
          // Parse the response JSON
          final responseData = jsonDecode(response.body);
          
          if (responseData.containsKey('audio') && responseData['audio'] != null) {
            print('Audio data received, length: ${responseData['audio'].length}');
            
            // Decode base64 to bytes
            final bytes = base64Decode(responseData['audio']);
            
            // Create a temporary file
            final tempDir = await getTemporaryDirectory();
            final file = File('${tempDir.path}/tts_response.mp3');
            await file.writeAsBytes(bytes);
            
            // Play the audio
            await _audioPlayer.setFilePath(file.path);
            await _audioPlayer.play();
            
            print('Playing TTS audio');
          } else {
            print('No audio data in response: $responseData');
          }
        } catch (e) {
          print('Error decoding or playing audio: $e');
        }
      } else {
        print('TTS API Error: ${response.statusCode}');
        print('Response: ${response.body}');
      }
    } catch (e) {
      print('TTS API Connection Error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final isDark = themeProvider.isDarkMode;
    final backgroundColor = isDark ? Colors.grey[900] : Colors.white;
    
    return Scaffold(
      backgroundColor: backgroundColor,
      // App bar with green background and back button
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () {
            Navigator.of(context).pop();
          },
        ),
        title: const Text('AI Assistant'),
        backgroundColor: AppTheme.grabGreen,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.bookmark_border),
            onPressed: () {},
          ),
          IconButton(
            icon: const Icon(Icons.more_vert),
            onPressed: () {},
          ),
        ],
      ),
      // Simple body with white background
      body: Column(
        children: [
          // Chat messages
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 20.0),
              itemCount: _messages.length,
              itemBuilder: (context, index) {
                final message = _messages[index];
                final isUser = message['sender'] == 'user';
                final hasImage = message.containsKey('image');
                
                return Padding(
                  padding: const EdgeInsets.only(bottom: 16.0),
                  child: Column(
                    crossAxisAlignment: isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                    children: [
                      Container(
                        constraints: BoxConstraints(
                          maxWidth: MediaQuery.of(context).size.width * 0.7,
                        ),
                        padding: const EdgeInsets.symmetric(horizontal: 13.0, vertical: 12.0),
                        decoration: BoxDecoration(
                          color: isUser 
                              ? AppTheme.grabGreen
                              : isDark ? Colors.grey[800] : Colors.grey[200],
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          message['message'],
                          style: TextStyle(
                            color: isUser ? Colors.white : isDark ? Colors.white : Colors.black,
                            fontSize: 15,
                            height: 1.2,
                          ),
                        ),
                      ),
                      
                      // Show AI generated image if exists
                      if (hasImage && !isUser)
                        Container(
                          margin: const EdgeInsets.only(top: 8),
                          width: 240,
                          height: 160,
                          decoration: BoxDecoration(
                            color: Colors.amber.shade50,
                            borderRadius: BorderRadius.circular(16),
                            image: DecorationImage(
                              image: AssetImage(message['image']),
                              fit: BoxFit.cover,
                            ),
                          ),
                        ),
                    ],
                  ),
                );
              },
            ),
          ),
    
          // Loading indicator
          if (_isSendingMessage)
            const Padding(
              padding: EdgeInsets.all(16.0),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 16,
                    backgroundColor: AppTheme.grabGreen,
                    child: Text(
                      'G',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  SizedBox(width: 16),
                  SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppTheme.grabGreen,
                    ),
                  ),
                ],
              ),
            ),
    
          // Input box with floating shadow effect
          Padding(
            padding: const EdgeInsets.only(bottom: 30.0),
            child: Center(
              child: Container(
                width: MediaQuery.of(context).size.width * 0.9,
                margin: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 1.0),
                decoration: BoxDecoration(
                  color: Colors.grey[200],
                  borderRadius: BorderRadius.circular(30),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.2),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                      spreadRadius: 0,
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    // Mic button inside on left
                    Padding(
                      padding: const EdgeInsets.only(left: 10.0),
                      child: IconButton(
                        icon: const Icon(
                          Icons.mic,
                          color: Colors.grey,
                        ),
                        onPressed: () {
                          if (_voiceProvider.isListening) {
                            _voiceProvider.stopListening();
                            setState(() {});
                          } else {
                            _voiceProvider.startListening();
                            setState(() {});
                          }
                        },
                      ),
                    ),
                    
                    // Text input in the middle
                    Expanded(
                      child: TextField(
                        controller: _chatController,
                        decoration: const InputDecoration(
                          hintText: 'Type message...',
                          hintStyle: TextStyle(
                            color: Colors.grey,
                          ),
                          border: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          errorBorder: InputBorder.none,
                          disabledBorder: InputBorder.none,
                          contentPadding: EdgeInsets.symmetric(vertical: 15),
                          fillColor: Colors.transparent,
                          filled: true,
                        ),
                        style: TextStyle(
                          color: isDark ? Colors.white : Colors.black,
                        ),
                        onSubmitted: (value) {
                          _sendMessage(value);
                        },
                      ),
                    ),
                    
                    // Send button inside on right
                    Padding(
                      padding: const EdgeInsets.only(right: 8.0),
                      child: Container(
                        width: 40,
                        height: 40,
                        decoration: const BoxDecoration(
                          color: AppTheme.grabGreen,
                          shape: BoxShape.circle,
                        ),
                        child: IconButton(
                          padding: EdgeInsets.zero,
                          icon: const Icon(
                            Icons.arrow_upward,
                            color: Colors.white,
                          ),
                          onPressed: () => _sendMessage(_chatController.text),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}