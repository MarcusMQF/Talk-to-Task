import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:audioplayers/audioplayers.dart';
import 'dart:convert';

class TTSIntegration extends StatefulWidget {
  @override
  _TTSIntegrationState createState() => _TTSIntegrationState();
}

class _TTSIntegrationState extends State<TTSIntegration> {
  final TextEditingController _textController = TextEditingController();
  final AudioPlayer _audioPlayer = AudioPlayer();
  String _audioBase64 = '';
  String _errorMessage = '';

  Future<void> _speakText(String text) async {
    setState(() {
      _errorMessage = '';
    });
    final apiUrl = Uri.parse('http://127.0.0.1:5000/'); // Replace with your API URL

    try {
      final response = await http.post(
        apiUrl,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'text': text}),
      );

      if (response.statusCode == 200) {
        final responseData = jsonDecode(response.body);
        setState(() {
          _audioBase64 = responseData['audio'];
        });
        if (_audioBase64.isNotEmpty) {
          final bytes = base64Decode(_audioBase64);
          await _audioPlayer.play(BytesSource(bytes));
        } else {
          setState(() {
            _errorMessage = 'No audio data received from the API.';
          });
        }
      } else {
        setState(() {
          _errorMessage = 'Failed to communicate with the API: ${response.statusCode}';
        });
        print('API Error: ${response.body}');
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Error connecting to the API: $e';
      });
      print('API Connection Error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        TextField(
          controller: _textController,
          decoration: InputDecoration(labelText: 'Enter text to speak'),
        ),
        ElevatedButton(
          onPressed: () {
            _speakText(_textController.text);
          },
          child: Text('Speak'),
        ),
        if (_errorMessage.isNotEmpty)
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Text(
              _errorMessage,
              style: TextStyle(color: Colors.red),
            ),
          ),
      ],
    );
  }

  @override
  void dispose() {
    _audioPlayer.dispose();
    super.dispose();
  }
}