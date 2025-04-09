from fastapi import FastAPI, UploadFile, File
from fastapi.responses import FileResponse
from rnnoise_wrapper import denoise_audio
import os

app = FastAPI()

@app.post("/denoise")
async def denoise_endpoint(file: UploadFile = File(...)):
    # Save uploaded file
    input_path = "uploaded_audio.wav"
    with open(input_path, "wb") as f:
        f.write(await file.read())
    
    # Denoise
    output_path = "denoised_audio.wav"
    denoise_audio(input_path, output_path)
    
    # Return the processed file
    return FileResponse(output_path)