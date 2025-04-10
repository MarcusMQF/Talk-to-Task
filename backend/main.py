from fastapi import FastAPI, UploadFile, File
from fastapi.middleware.cors import CORSMiddleware
import whisper
from transformers import WhisperForConditionalGeneration, WhisperProcessor
import tempfile
import os
import torch
import asyncio
from pathlib import Path

PROJECT_ROOT = Path(__file__).parent
MODEL_CACHE_DIR = PROJECT_ROOT / "models" / "huggingface"
MODEL_CACHE_DIR.mkdir(parents=True, exist_ok=True)

app = FastAPI()

# Configure CORS
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

torch.set_num_threads(1)

# Model mappings for different countries
COUNTRY_MODELS = {
    "Singapore": "jensenlwt/whisper-small-singlish-122k",
    "Indonesia": "NafishZaldinanda/whisper-small-indonesian",
    "Malaysia": "mesolitica/malaysian-whisper-small-v3"
    # Add more mappings as needed
}

# Initialize model cache
fine_tuned_models = {}
processors = {}

def download_model(model_id: str):
    """Download and cache model files"""
    try:
        print(f"Downloading model: {model_id}")
        model_specific_cache = MODEL_CACHE_DIR / model_id.replace('/', '_')
        
        # Force download and save to our cache directory
        model = WhisperForConditionalGeneration.from_pretrained(
            model_id,
            cache_dir=model_specific_cache,
            local_files_only=False  # Force download from HuggingFace
        )
        processor = WhisperProcessor.from_pretrained(
            model_id,
            cache_dir=model_specific_cache,
            local_files_only=False  # Force download from HuggingFace
        )
        
        print(f"Model downloaded to: {model_specific_cache}")
        return model, processor
    except Exception as e:
        print(f"Error downloading model {model_id}: {str(e)}")
        return None, None

# Download all models at startup
print("Initializing models...")
for country, model_id in COUNTRY_MODELS.items():
    print(f"Setting up model for {country}")
    model_path = MODEL_CACHE_DIR / model_id.replace('/', '_')
    
    if not model_path.exists():
        model, processor = download_model(model_id)
        if model and processor:
            fine_tuned_models[model_id] = model
            processors[model_id] = processor
            if torch.cuda.is_available():
                fine_tuned_models[model_id] = fine_tuned_models[model_id].to("cuda")
    else:
        print(f"Loading cached model for {country}")
        try:
            fine_tuned_models[model_id] = WhisperForConditionalGeneration.from_pretrained(
                model_path,
                local_files_only=True
            )
            processors[model_id] = WhisperProcessor.from_pretrained(
                model_path,
                local_files_only=True
            )
            if torch.cuda.is_available():
                fine_tuned_models[model_id] = fine_tuned_models[model_id].to("cuda")
        except Exception as e:
            print(f"Error loading cached model for {country}: {str(e)}")

# Initialize base Whisper model first
print("Loading base Whisper model...")
base_model = None
try:
    base_model = whisper.load_model(
        "base", 
        device="cuda" if torch.cuda.is_available() else "cpu",
        download_root=str(PROJECT_ROOT / "models" / "whisper")
    )
    print("Base model loaded successfully")
except Exception as e:
    print(f"Error loading base model: {str(e)}")
    raise RuntimeError("Failed to load base Whisper model")

async def transcribe_with_base_model(file_path: str):
    """Transcribe audio using the base Whisper model"""
    try:
        print("Starting base model transcription...")
        result = base_model.transcribe(file_path)
        print(f"Base model transcription complete: {result['text']}")
        return result["text"]
    except Exception as e:
        print(f"Error in base model transcription: {str(e)}")
        return "Base model transcription failed"

@app.post("/transcribe/")
async def transcribe_audio(
    file: UploadFile = File(...),
    latitude: float = None,
    longitude: float = None,
    country: str = None
):
    try:
        print(f"Received request - Country: {country}, Lat: {latitude}, Long: {longitude}")
        
        # Save uploaded file
        with tempfile.NamedTemporaryFile(delete=False, suffix='.m4a') as temp_file:
            content = await file.read()
            temp_file.write(content)
            temp_path = temp_file.name
            print(f"Saved audio file to: {temp_path}")

        # Always run base model transcription
        base_result = await transcribe_with_base_model(temp_path)
        print(f"Base model result: {base_result}")

        # Try fine-tuned model if country is supported
        fine_tuned_result = None
        fine_tuned_model_id = None
        if country in COUNTRY_MODELS:
            fine_tuned_model_id = COUNTRY_MODELS[country]
            fine_tuned_result = await transcribe_with_fine_tuned_model(temp_path, country)

        # Clean up temp file
        os.unlink(temp_path)

        # Prepare response
        response_data = {
            "base_model": {
                "text": base_result,
                "model": "whisper-base"
            },
            "fine_tuned_model": {
                "text": fine_tuned_result,
                "model": fine_tuned_model_id
            } if fine_tuned_result else None,
            "location": {
                "latitude": latitude,
                "longitude": longitude,
                "country": country
            } if all([latitude, longitude, country]) else None
        }
        
        print(f"Sending response: {response_data}")
        return response_data

    except Exception as e:
        print(f"Error in transcribe_audio: {str(e)}")
        import traceback
        traceback.print_exc()
        return {"error": str(e)}

async def transcribe_with_fine_tuned_model(file_path: str, country: str):
    try:
        if not country in COUNTRY_MODELS:
            return None
            
        model_id = COUNTRY_MODELS[country]
        if model_id not in fine_tuned_models:
            print(f"Model not loaded for {country}, attempting to download...")
            model, processor = download_model(model_id)
            if not model or not processor:
                return None
            fine_tuned_models[model_id] = model
            processors[model_id] = processor
            if torch.cuda.is_available():
                fine_tuned_models[model_id] = fine_tuned_models[model_id].to("cuda")

        model = fine_tuned_models[model_id]
        processor = processors[model_id]

        # Run CPU-intensive tasks in a thread pool
        input_features = await asyncio.to_thread(
            processor, file_path, return_tensors="pt"
        )
        input_features = input_features.input_features

        if torch.cuda.is_available():
            input_features = input_features.to("cuda")

        predicted_ids = await asyncio.to_thread(
            model.generate, input_features
        )
        
        transcription = processor.batch_decode(predicted_ids, skip_special_tokens=True)[0]
        return transcription
    except Exception as e:
        print(f"Error in fine-tuned model transcription: {str(e)}")
        return None

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000, log_level="debug")