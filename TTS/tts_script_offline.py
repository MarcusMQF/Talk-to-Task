# offline, no Google Translate
import pyttsx3

# Initialize the speech engine
engine = pyttsx3.init()

# Optional: Set speech rate
engine.setProperty('rate', 150)  # words per minute

# Optional: Set volume (0.0 to 1.0)
engine.setProperty('volume', 0.8)

# Optional: Get and set a specific voice
voices = engine.getProperty('voices')
# for voice in voices:
#     print("Voice:", voice.name, voice.id)
# engine.setProperty('voice', voices[0].id) # Example: Use the first available voice

# The text you want to speak
text_to_speak = "Hello, I don't know anything about the code."

# Say the text
engine.say(text_to_speak)

# Wait for the speech to finish
engine.runAndWait()

# Stop the engine
engine.stop()
