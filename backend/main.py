from fastapi import FastAPI, UploadFile, File
from fastapi.middleware.cors import CORSMiddleware
import whisper
import tempfile
import os
import torch

app = FastAPI()

# Configure CORS
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Initialize Whisper model
model = whisper.load_model("base", device="cuda" if torch.cuda.is_available() else "cpu", download_root="models")

@app.post("/transcribe/")
async def transcribe_audio(
    file: UploadFile = File(...),
    latitude: float = None,
    longitude: float = None,
    country: str = None
):
    try:
        # Save uploaded file to temp directory
        with tempfile.NamedTemporaryFile(delete=False, suffix='.m4a') as temp_file:
            content = await file.read()
            temp_file.write(content)
            temp_path = temp_file.name

        # Transcribe audio
        result = model.transcribe(temp_path, language="en")
        
        # Clean up temp file
        os.unlink(temp_path)
        
        response = {
            "text": result["text"],
            "location": {
                "latitude": latitude,
                "longitude": longitude,
                "country": country
            } if latitude and longitude else None
        }
        
        return response
    except Exception as e:
        return {"error": str(e)}

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)