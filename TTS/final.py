# recognize the language of the text, and if it is not in default language (English), automatically translate it to English, then only speak the translated text
from gtts import gTTS
import os
import platform
from langdetect import detect, LangDetectException
from googletrans import Translator

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
        return DEFAULT_LANGUAGE  # Assume default if detection fails
    except Exception as e:
        print(f"Language detection error: {e}")
        return DEFAULT_LANGUAGE

def speak_text(text, lang=DEFAULT_LANGUAGE):
    tts = gTTS(text=text, lang=lang, slow=False)
    filename = "translated_output.mp3"
    try:
        tts.save(filename)
        print(f"Audio file saved as: {filename} (spoken in {lang})")
        play_audio(filename)
    except Exception as e:
        print(f"Error during TTS generation: {e}")
        try:
            os.remove(filename)
        except FileNotFoundError:
            pass

def play_audio(filename):
    print(f"Attempting to play: {filename}")
    system = platform.system()
    if system == "Linux":
        os.system(f"mpg321 {filename}")
    elif system == "Darwin":  # macOS
        os.system(f"afplay {filename}")
    elif system == "Windows":
        try:
            os.system(f'start "" "{filename}"')
        except Exception as e:
            print(f"Error using 'start' command: {e}")
            print("Trying a simpler start command.")
            os.system(f'start {filename}')
    else:
        print(f"Unsupported operating system for automatic playback. The audio file '{filename}' has been saved.")

if __name__ == "__main__":
    text_to_speak = input("Enter text to speak: ")
    detected_language = detect_language(text_to_speak)
    print(f"Detected language: {detected_language}")

    if detected_language != DEFAULT_LANGUAGE:
        print(f"Translating from {detected_language} to {DEFAULT_LANGUAGE}...")
        translated_text = translate_text(text_to_speak)
        if translated_text:
            print(f"Translated text: {translated_text}")
            speak_text(translated_text, DEFAULT_LANGUAGE)
        else:
            print("Translation failed. Speaking original text in default language.")
            speak_text(text_to_speak, DEFAULT_LANGUAGE)
    else:
        print("Text is already in the default language (English).")
        speak_text(text_to_speak, DEFAULT_LANGUAGE)


#pip install langdetect googletrans==4.0.0rc1