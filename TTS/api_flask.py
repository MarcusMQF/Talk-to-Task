from flask import Flask, request, jsonify
from gtts import gTTS
from langdetect import detect, LangDetectException
from googletrans import Translator
import os
import base64
from io import BytesIO
from flask_cors import CORS  # For handling Cross-Origin Requests

app = Flask(__name__)
CORS(app)  # Enable CORS for all routes (adjust as needed for security)
DEFAULT_LANGUAGE = 'en'

def translate_text(text, target_language=DEFAULT_LANGUAGE):
    translator = Translator()
    try:
        translation = translator.translate(text, dest=target_language)
        return translation.text
    except Exception as e:
        print(f"Translation error: {e}")
        return None

def detect_language(text):
    try:
        return detect(text)
    except LangDetectException:
        return DEFAULT_LANGUAGE
    except Exception as e:
        print(f"Language detection error: {e}")
        return DEFAULT_LANGUAGE

def text_to_speech(text, lang=DEFAULT_LANGUAGE):
    try:
        tts = gTTS(text=text, lang=lang, slow=False)
        audio_output = BytesIO()
        tts.write_to_fp(audio_output)
        audio_output.seek(0)
        return audio_output.read()
    except Exception as e:
        print(f"TTS error: {e}")
        return None

@app.route('/tts', methods=['POST'])
def tts_endpoint():
    data = request.get_json()
    if not data or 'text' not in data:
        return jsonify({'error': 'Missing "text" in request'}), 400

    text_to_speak = data['text']
    detected_language = detect_language(text_to_speak)

    if detected_language != DEFAULT_LANGUAGE:
        print(f"Detected language: {detected_language}, translating to {DEFAULT_LANGUAGE}")
        translated_text = translate_text(text_to_speak)
        if translated_text:
            audio_data = text_to_speech(translated_text, DEFAULT_LANGUAGE)
            if audio_data:
                return jsonify({'audio': base64.b64encode(audio_data).decode('utf-8')}), 200
            else:
                return jsonify({'error': 'TTS failed after translation'}), 500
        else:
            return jsonify({'error': 'Translation failed'}), 500
    else:
        print(f"Text is in default language ({DEFAULT_LANGUAGE})")
        audio_data = text_to_speech(text_to_speak, DEFAULT_LANGUAGE)
        if audio_data:
            return jsonify({'audio': base64.b64encode(audio_data).decode('utf-8')}), 200
        else:
            return jsonify({'error': 'TTS failed'}), 500

if __name__ == '__main__':
    app.run(debug=True, host='0.0.0.0', port=5000)