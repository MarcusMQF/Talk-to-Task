from fastapi import FastAPI, HTTPException
from pydantic import BaseModel
from gtts import gTTS
from langdetect import detect, LangDetectException
from googletrans import Translator
import os
from io import BytesIO
import base64
from fastapi.middleware.cors import CORSMiddleware

app = FastAPI()

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],  # Adjust as needed for security
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

DEFAULT_LANGUAGE = 'en'

class TTSRequest(BaseModel):
    text: str

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
        raise HTTPException(status_code=500, detail="TTS generation failed")

@app.post("/tts")
async def generate_tts(request: TTSRequest):
    text_to_speak = request.text
    detected_language = detect_language(text_to_speak)

    if detected_language != DEFAULT_LANGUAGE:
        print(f"Detected language: {detected_language}, translating to {DEFAULT_LANGUAGE}")
        translated_text = translate_text(text_to_speak)
        if translated_text:
            audio_data = text_to_speech(translated_text, DEFAULT_LANGUAGE)
            return {"audio": base64.b64encode(audio_data).decode('utf-8')}
        else:
            raise HTTPException(status_code=500, detail="Translation failed")
    else:
        print(f"Text is in default language ({DEFAULT_LANGUAGE})")
        audio_data = text_to_speech(text_to_speak, DEFAULT_LANGUAGE)
        return {"audio": base64.b64encode(audio_data).decode('utf-8')}

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)