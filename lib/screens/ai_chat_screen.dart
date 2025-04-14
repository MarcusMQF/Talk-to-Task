import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../constants/app_theme.dart';
import '../providers/voice_assistant_provider.dart';
import '../providers/theme_provider.dart';
import '../services/gemini_service.dart';
import 'package:flutter_tts/flutter_tts.dart';

class AIChatScreen extends StatefulWidget {
  const AIChatScreen({super.key});

  @override
  State<AIChatScreen> createState() => _AIChatScreenState();
}

class _AIChatScreenState extends State<AIChatScreen> with SingleTickerProviderStateMixin {
  final TextEditingController _chatController = TextEditingController();
  final List<Map<String, dynamic>> _messages = [
    {
      'sender': 'ai', 
      'message': 'Hi! How are you today? Can I help you?',
      'timestamp': DateTime.now().toString(),
    },
  ]; // Initial welcome message

  bool _isSendingMessage = false;
  bool _isSpeaking = false;
  late VoiceAssistantProvider _voiceProvider;
  final GeminiService _geminiService = GeminiService();
  final FlutterTts _flutterTts = FlutterTts();
  final ScrollController _scrollController = ScrollController();
  
  // Animation controller for mic button
  late AnimationController _animationController;
  late Animation<double> _pulseAnimation;

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
    
    // Initialize TTS
    _initializeTts();
    
    // Initialize animation controller for mic button
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 1000),
      vsync: this,
    );
    
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.3).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: Curves.easeInOut,
      ),
    );
    
    // Speak the initial welcome message
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _speakAIResponse(_messages.first['message']!);
    });
  }

  Future<void> _initializeTts() async {
    await _flutterTts.setLanguage("en-US");
    await _flutterTts.setSpeechRate(0.5); // Slightly slower for better comprehension
    await _flutterTts.setVolume(1.0);
    await _flutterTts.setPitch(1.0);

    // Set up completion listener
    _flutterTts.setCompletionHandler(() {
      setState(() {
        _isSpeaking = false;
      });
    });
  }

  @override
  void dispose() {
    _voiceProvider.removeCommandCallback();
    _chatController.dispose();
    _flutterTts.stop();
    _scrollController.dispose();
    _animationController.dispose();
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
    
    if (text.isEmpty) return;

    // Stop any ongoing speech
    if (_isSpeaking) {
      await _flutterTts.stop();
    }

    setState(() {
      _isSpeaking = true;
    });

    // Clean up the text - remove markdown formatting if needed
    String cleanText = text.replaceAll('*', '').replaceAll('#', '').replaceAll('_', '');

    await _flutterTts.speak(cleanText);
  }
  
  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final isDark = themeProvider.isDarkMode;
    final backgroundColor = isDark ? Colors.grey[900] : Colors.white;
    
    // Listen to voice assistant state changes
    final voiceState = _voiceProvider.state;
    final voiceError = _voiceProvider.errorMessage;
    
    // Control animation based on state
    if (voiceState == VoiceAssistantState.listening) {
      _animationController.repeat(reverse: true);
    } else {
      if (_animationController.isAnimating) {
        _animationController.stop();
        _animationController.reset();
      }
    }
    
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
          // Error message if voice recognition fails
          if (voiceState == VoiceAssistantState.error && voiceError.isNotEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
              color: Colors.red.shade700,
              child: Row(
                children: [
                  const Icon(Icons.error_outline, color: Colors.white, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Voice recognition error: $voiceError',
                      style: const TextStyle(color: Colors.white, fontSize: 12),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white, size: 18),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    onPressed: () => _voiceProvider.reset(),
                  ),
                ],
              ),
            ),
          
          // Processing status indicator
          if (voiceState == VoiceAssistantState.processing)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
              color: Colors.blue.shade700,
              child: const Row(
                children: [
                  SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  ),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Processing your speech...',
                      style: TextStyle(color: Colors.white, fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
            
          // Chat messages
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20.0),
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
                          maxWidth: MediaQuery.of(context).size.width * 0.55,
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
                      child: _buildMicButton(voiceState),
                    ),
                    
                    // Text input in the middle
                    Expanded(
                      child: TextField(
                        controller: _chatController,
                        decoration: InputDecoration(
                          hintText: voiceState == VoiceAssistantState.processing 
                              ? 'Processing speech...' 
                              : voiceState == VoiceAssistantState.listening
                                  ? 'Listening...'
                                  : 'Type message...',
                          hintStyle: TextStyle(
                            color: voiceState == VoiceAssistantState.processing || 
                                  voiceState == VoiceAssistantState.listening
                                ? AppTheme.grabGreen
                                : Colors.grey,
                          ),
                          border: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          errorBorder: InputBorder.none,
                          disabledBorder: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(vertical: 15),
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
  
  // Helper method to build mic button with different states
  Widget _buildMicButton(VoiceAssistantState state) {
    switch (state) {
      case VoiceAssistantState.listening:
        return ScaleTransition(
          scale: _pulseAnimation,
          child: IconButton(
            icon: const Icon(
              Icons.mic,
              color: AppTheme.grabGreen,
            ),
            onPressed: () {
              _voiceProvider.stopListening();
            },
            tooltip: 'Stop listening',
          ),
        );
      case VoiceAssistantState.processing:
        return Container(
          width: 40,
          height: 40,
          padding: const EdgeInsets.all(8),
          child: const CircularProgressIndicator(
            strokeWidth: 2,
            color: AppTheme.grabGreen,
          ),
        );
      case VoiceAssistantState.error:
        return IconButton(
          icon: const Icon(
            Icons.mic_off,
            color: Colors.red,
          ),
          onPressed: () {
            _voiceProvider.reset();
            _voiceProvider.startListening();
          },
          tooltip: 'Retry',
        );
      default:
        return IconButton(
          icon: const Icon(
            Icons.mic_none,
            color: Colors.grey,
          ),
          onPressed: () {
            _voiceProvider.startListening();
          },
          tooltip: 'Tap to speak',
        );
    }
  }
}