import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../constants/app_theme.dart';
import '../providers/voice_assistant_provider.dart';

class AIChatScreen extends StatefulWidget {
  const AIChatScreen({super.key});

  @override
  State<AIChatScreen> createState() => _AIChatScreenState();
}

class _AIChatScreenState extends State<AIChatScreen> {
  final TextEditingController _chatController = TextEditingController();
  final List<Map<String, String>> _messages = [
    {'sender': 'ai', 'message': 'What can I help you today?'},
  {'sender': 'driver', 'message': 'Accept the upcoming request.'},
    {'sender': 'ai', 'message': 'Accepted the ride, would you like me to message them you’re on your way?'},
    {'sender': 'driver', 'message': 'Yes.'},
    {'sender': 'ai', 'message': 'Message sent!'},
  ]; // Predefined messages for the demo

bool _isListening = false; // Indicator for listening state
  bool _isProcessing = false; // Indicator for processing state

  @override
  void initState() {
    super.initState();

    // Set up the callback to handle recognized text
    final voiceProvider = Provider.of<VoiceAssistantProvider>(context, listen: false);
    voiceProvider.setCommandCallback((recognizedText) {
      setState(() {
        _isProcessing = false; // Stop processing indicator
        _chatController.text = recognizedText; // Add recognized text to the chat box
        _sendMessage(recognizedText); // Automatically send the message
      });
    });
  }

  @override
  void dispose() {
    // Remove the callback when the screen is disposed
    final voiceProvider = Provider.of<VoiceAssistantProvider>(context, listen: false);
    voiceProvider.removeCommandCallback();
    super.dispose();
  }
  
  void _sendMessage(String message) {
    if (message.trim().isEmpty) return;

    setState(() {
      _messages.add({'sender': 'driver', 'message': message});
    });

    _chatController.clear();

    // Simulate AI response
    Future.delayed(const Duration(milliseconds: 500), () {
      setState(() {
        _messages.add({'sender': 'ai', 'message': 'This is a response from the AI assistant.'});
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Grab Assistant'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
      ),
      body: Column(
        children: [
          // Chat messages
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(16.0),
              itemCount: _messages.length,
              itemBuilder: (context, index) {
                final message = _messages[index];
                final isDriver = message['sender'] == 'driver';

                return Align(
                  alignment: isDriver ? Alignment.centerRight : Alignment.centerLeft,
                  child: Container(
                    margin: const EdgeInsets.symmetric(vertical: 8.0),
                    padding: const EdgeInsets.all(12.0),
                    decoration: BoxDecoration(
                      color: isDriver ? AppTheme.grabGreen : AppTheme.grabGrayDark,
                      borderRadius: BorderRadius.only(
                        topLeft: const Radius.circular(12),
                        topRight: const Radius.circular(12),
                        bottomLeft: isDriver ? const Radius.circular(12) : Radius.zero,
                        bottomRight: isDriver ? Radius.zero : const Radius.circular(12),
                      ),
                    ),
                    child: Text(
                      message['message']!,
                      style: TextStyle(
                        color: isDriver ? Colors.white : Colors.white,
                        fontSize: 14,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),

          // Listening and Processing Indicators
          if (_isListening)
            const Padding(
              padding: EdgeInsets.all(8.0),
              child: Text(
                'Listening...',
                style: TextStyle(color: AppTheme.grabGreen, fontSize: 16),
              ),
            ),
          if (_isProcessing)
            const Padding(
              padding: EdgeInsets.all(8.0),
              child: Text(
                'Processing audio...',
                style: TextStyle(color: AppTheme.grabGreen, fontSize: 16),
              ),
            ),

          // Input box and bottom navigation
          Column(
            children: [
              // Input box
              Padding(
                padding: const EdgeInsets.all(8.0),
                child: Row(
                  children: [
                    // Text input
                    Expanded(
                      child: TextField(
                        controller: _chatController,
                        decoration: InputDecoration(
                          hintText: 'Type your message...',
                          filled: true,
                          fillColor: Colors.white,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(30),
                            borderSide: BorderSide.none,
                          ),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        ),
                        onSubmitted: (value) {
                          _sendMessage(value); // Send the message when Enter is pressed
                        },
                        style: const TextStyle(fontSize: 16, color: AppTheme.grabBlack),                
                      ),
                    ),

                    const SizedBox(width: 8),

                    // Send button
                    GestureDetector(
                      onTap: () => _sendMessage(_chatController.text),
                      child: CircleAvatar(
                        backgroundColor: AppTheme.grabGreen,
                        child: const Icon(Icons.send, color: Colors.white),
                      ),
                    ),
                  ],
                ),
              ),

              // Bottom navigation bar
              Container(
                color: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 8.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.menu, color: AppTheme.grabGrayDark),
                      onPressed: () {},
                    ),
                    IconButton(
                      icon: const Icon(Icons.mic, color: AppTheme.grabGreen),
                      onPressed: () {
                        final voiceProvider = Provider.of<VoiceAssistantProvider>(context, listen: false);
                        if (voiceProvider.isListening) {
                          voiceProvider.stopListening();
                          setState(() {
                            _isListening = false; // Stop listening indicator
                          });
                        } else {
                          voiceProvider.startListening();
                          setState(() {
                            _isListening = true; // Show listening indicator
                            _isProcessing = true; // Show processing indicator
                          });
                        }
                      },
                    ),
                    IconButton(
                      icon: const Icon(Icons.map, color: AppTheme.grabGrayDark),
                      onPressed: () {},
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}