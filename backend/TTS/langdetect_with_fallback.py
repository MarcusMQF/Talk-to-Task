# langdetect_with_fallback.py
from langdetect import detect

DEFAULT_LANGUAGE = 'en'  # Set English as the default language

def detect_and_fallback(text, default_lang=DEFAULT_LANGUAGE):
    try:
        detected_lang = detect(text)
        if detected_lang == default_lang:
            return detected_lang
        else:
            print(f"Detected language '{detected_lang}' is not the default ('{default_lang}'). Using default.")
            return default_lang
    except Exception as e:
        print(f"Error during language detection: {e}")
        print(f"Falling back to default language: {default_lang}")
        return default_lang

if __name__ == "__main__":
    text1 = "Hello, how are you today?"
    lang1 = detect_and_fallback(text1)
    print(f"'{text1}' will be processed as: {lang1}")

    text2 = "Selamat pagi, apa khabar?"
    lang2 = detect_and_fallback(text2)
    print(f"'{text2}' will be processed as: {lang2}")

    text3 = "こんにちは、元気ですか？"
    lang3 = detect_and_fallback(text3)
    print(f"'{text3}' will be processed as: {lang3}")

    text4 = "This is also in English."
    lang4 = detect_and_fallback(text4)
    print(f"'{text4}' will be processed as: {lang4}")