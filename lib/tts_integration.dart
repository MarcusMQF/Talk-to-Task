import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:just_audio/just_audio.dart';
import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';

class TTSIntegration extends StatefulWidget {
  const TTSIntegration({Key? key}) : super(key: key);

  @override
  _TTSIntegrationState createState() => _TTSIntegrationState();
}

class _TTSIntegrationState extends State<TTSIntegration> {
  final TextEditingController _textController = TextEditingController();
  final AudioPlayer _audioPlayer = AudioPlayer();
  String _audioBase64 = '';
  String _errorMessage = '';
  bool _isLoading = false;

  Future<void> _speakText(String text) async {
    if (text.isEmpty) {
      setState(() {
        _errorMessage = 'Please enter some text to speak.';
      });
      return;
    }

    setState(() {
      _errorMessage = '';
      _isLoading = true;
    });

    final apiUrl = Uri.parse('http://127.0.0.1:5000/tts'); // Fixed endpoint URL with /tts

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
          await _playBase64Audio(_audioBase64);
        } else {
          setState(() {
            _errorMessage = 'No audio data received from the API.';
            _isLoading = false;
          });
        }
      } else {
        setState(() {
          _errorMessage = 'Failed to communicate with the API: ${response.statusCode}';
          _isLoading = false;
        });
        print('API Error: ${response.body}');
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Error connecting to the API: $e';
        _isLoading = false;
      });
      print('API Connection Error: $e');
    }
  }

  Future<void> _playBase64Audio(String base64Audio) async {
    try {
      // Decode the base64 string to bytes
      final bytes = base64Decode(base64Audio);
      
      // Create a temporary file to store the audio
      final tempDir = await getTemporaryDirectory();
      final file = File('${tempDir.path}/temp_audio.mp3');
      await file.writeAsBytes(bytes);
      
      // Play the audio
      await _audioPlayer.setFilePath(file.path);
      await _audioPlayer.play();
      
      setState(() {
        _isLoading = false;
      });
      
      // Clean up the temporary file when done
      _audioPlayer.playerStateStream.listen((state) {
        if (state.processingState == ProcessingState.completed) {
          // ignore: invalid_return_type_for_catch_error
          file.delete().catchError((e) => print('Error deleting temp file: $e'));
        }
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'Error playing audio: $e';
        _isLoading = false;
      });
      print('Audio Playback Error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        TextField(
          controller: _textController,
          decoration: const InputDecoration(labelText: 'Enter text to speak'),
        ),
        const SizedBox(height: 16),
        ElevatedButton(
          onPressed: _isLoading ? null : () => _speakText(_textController.text),
          child: _isLoading 
              ? const SizedBox(
                  width: 20, 
                  height: 20, 
                  child: CircularProgressIndicator(strokeWidth: 2)
                )
              : const Text('Speak'),
        ),
        if (_errorMessage.isNotEmpty)
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Text(
              _errorMessage,
              style: const TextStyle(color: Colors.red),
            ),
          ),
      ],
    );
  }

  @override
  void dispose() {
    _audioPlayer.dispose();
    _textController.dispose();
    super.dispose();
  }
}