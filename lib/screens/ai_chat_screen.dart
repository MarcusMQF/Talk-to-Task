import 'package:flutter/material.dart';
import '../constants/app_theme.dart';

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
                      onPressed: () {},
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