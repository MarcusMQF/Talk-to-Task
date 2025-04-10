from fastapi import FastAPI, UploadFile, File, Form
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from fastapi.encoders import jsonable_encoder
import whisper
from transformers import WhisperForConditionalGeneration, WhisperProcessor, pipeline
import tempfile
import os
import torch
import asyncio
from pathlib import Path
import librosa
from transformers.models.whisper import tokenization_whisper
import time  # Add this import at the top

# Add this for Malaysian model
tokenization_whisper.TASK_IDS = ["translate", "transcribe", "transcribeprecise"]

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

# Updated model configurations with clearer country labeling
COUNTRY_MODELS = {
    "Malaysia": {
        "name": "Malaysian Whisper Model",
        "model_id": "mesolitica/malaysian-whisper-small-v3",
        "language": "ms",
        "type": "malaysian"
    },
    "Singapore": {
        "name": "Singlish Whisper Model",
        "model_id": "jensenlwt/whisper-small-singlish-122k",
        "language": "en",
        "type": "pipeline"
    },
    "Thailand": {
        "name": "Thai Whisper Model",
        "model_id": "juierror/whisper-tiny-thai",
        "language": "Thai",
        "type": "thai"
    }
}

class ModelHandler:
    def __init__(self, model_config, cache_dir):
        self.config = model_config
        self.cache_dir = cache_dir
        self.model = None
        self.processor = None
        self.pipeline = None
        self.device = "cpu"  # Always use CPU

    async def load(self):
        try:
            model_type = self.config["type"]
            model_id = self.config["model_id"]
            
            if model_type == "pipeline":
                print(f"Loading pipeline model: {model_id}")
                try:
                    # Create pipeline directly
                    self.pipeline = pipeline(
                        task="automatic-speech-recognition",
                        model=model_id,
                        chunk_length_s=30,
                        device=self.device
                    )
                    print(f"Pipeline model loaded successfully: {model_id}")
                    return True
                except Exception as e:
                    print(f"Error creating pipeline: {str(e)}")
                    raise
            
            elif model_type == "malaysian":
                print(f"Loading Malaysian model: {model_id}")
                # Load processor first
                self.processor = WhisperProcessor.from_pretrained(
                    model_id,
                    cache_dir=self.cache_dir
                )
                
                # Load model for CPU
                self.model = WhisperForConditionalGeneration.from_pretrained(
                    model_id,
                    cache_dir=self.cache_dir,
                    torch_dtype=torch.float32  # Use float32 for CPU
                ).to(self.device)
                
                # Set to eval mode
                self.model.eval()
                print("Malaysian model loaded successfully")
                
            else:
                print(f"Loading custom model: {model_id}")
                self.processor = WhisperProcessor.from_pretrained(
                    model_id,
                    cache_dir=self.cache_dir,
                    language=self.config["language"],
                    task="transcribe"
                )
                
                self.model = WhisperForConditionalGeneration.from_pretrained(
                    model_id,
                    cache_dir=self.cache_dir
                ).to(self.device)
            
            return True
        except Exception as e:
            print(f"Error loading model {model_id}: {str(e)}")
            import traceback
            traceback.print_exc()
            return False

    async def transcribe(self, file_path: str):
        try:
            if self.config["type"] == "pipeline":
                return await self._transcribe_pipeline(file_path)
            elif self.config["type"] == "malaysian":
                return await self._transcribe_malaysian(file_path)
            else:
                return await self._transcribe_thai(file_path)
        except Exception as e:
            print(f"Error in transcription: {str(e)}")
            return None

    async def _transcribe_pipeline(self, file_path: str):
        try:
            print(f"Transcribing with pipeline model...")
            if self.pipeline is None:
                raise RuntimeError("Pipeline not initialized")
                
            # Use direct file path for pipeline
            result = await asyncio.to_thread(
                self.pipeline, 
                file_path,
                batch_size=8,
                return_timestamps=False
            )
            
            print(f"Pipeline transcription result: {result}")
            return result["text"] if isinstance(result, dict) else result
        except Exception as e:
            print(f"Error in pipeline transcription: {str(e)}")
            import traceback
            traceback.print_exc()
            return None

    async def _transcribe_malaysian(self, file_path: str):
        try:
            audio, sr = await asyncio.to_thread(
                librosa.load, 
                file_path, 
                sr=16000,
                mono=True
            )
            
            print(f"Loaded audio: {len(audio)} samples, {sr}Hz")

            # Process audio
            with torch.no_grad():
                inputs = self.processor(
                    audio, 
                    sampling_rate=16000, 
                    return_tensors="pt"
                )
                
                # Move input features to CPU
                input_features = inputs["input_features"].to(self.device)
                
                # Generate transcription
                generated = await asyncio.to_thread(
                    self.model.generate,
                    input_features,
                    language="ms",
                    task="transcribe"
                )
                
                # Decode result
                transcription = self.processor.batch_decode(
                    generated, 
                    skip_special_tokens=True
                )[0]
                
                print(f"Malaysian model transcription: {transcription}")
                return transcription

        except Exception as e:
            print(f"Error in Malaysian transcription: {str(e)}")
            import traceback
            traceback.print_exc()
            return None

    async def _transcribe_thai(self, file_path: str):
        try:
            print("Starting Thai transcription...")
            audio, sr = await asyncio.to_thread(librosa.load, file_path, sr=16000)
            inputs = self.processor(
                audio, 
                sampling_rate=16000, 
                return_tensors="pt"
            ).input_features
            
            generated = await asyncio.to_thread(
                self.model.generate,
                input_features=inputs.to(self.device),
                max_new_tokens=255,
                language="th",  # Explicitly set Thai language
                task="transcribe"
            )
            
            # Get transcription and ensure proper encoding
            transcription = self.processor.batch_decode(generated, skip_special_tokens=True)[0]
            print(f"Thai transcription (raw): {transcription.encode('utf-8')}")
            
            return transcription

        except Exception as e:
            print(f"Error in Thai transcription: {str(e)}")
            import traceback
            traceback.print_exc()
            return None

# Initialize model handlers
model_handlers = {}

async def initialize_models():
    """Initialize all models asynchronously"""
    print("Initializing models...")
    
    # Initialize base Whisper model first
    print("Loading base Whisper model...")
    global base_model
    try:
        base_model = whisper.load_model(
            "base", 
            device="cpu",  # Always use CPU
            download_root=str(PROJECT_ROOT / "models" / "whisper")
        )
        print("Base model loaded successfully")
    except Exception as e:
        print(f"Error loading base model: {str(e)}")
        raise RuntimeError("Failed to load base Whisper model")

    # Initialize fine-tuned models
    for country, config in COUNTRY_MODELS.items():
        print(f"Setting up model for {country}")
        model_specific_cache = MODEL_CACHE_DIR / config["model_id"].replace('/', '_')
        handler = ModelHandler(config, model_specific_cache)
        await handler.load()
        model_handlers[country] = handler

    print("Model initialization complete")

@app.on_event("startup")
async def startup_event():
    """Initialize models when the FastAPI app starts"""
    await initialize_models()

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
    country: str = Form(None)
):
    try:
        print("\n=== Received Request ===")
        print(f"Country: '{country}'")
        start_time = time.time()  # Start timing

        # Save uploaded file
        with tempfile.NamedTemporaryFile(delete=False, suffix='.m4a') as temp_file:
            content = await file.read()
            temp_file.write(content)
            temp_path = temp_file.name
            print(f"File saved at: {temp_path}")

        # Create tasks for both models
        print("Starting parallel transcription...")
        base_task = asyncio.create_task(transcribe_with_base_model(temp_path))
        fine_tuned_task = asyncio.create_task(
            transcribe_with_fine_tuned_model(temp_path, country)
        ) if country in COUNTRY_MODELS else None

        # Run both tasks in parallel
        if fine_tuned_task:
            base_result, fine_tuned_result = await asyncio.gather(base_task, fine_tuned_task)
        else:
            base_result = await base_task
            fine_tuned_result = None

        # Clean up
        os.unlink(temp_path)

        # Calculate elapsed time
        elapsed_time = time.time() - start_time

        response_data = {
            "base_model": {
                "text": base_result,
                "model": "whisper-base"
            },
            "fine_tuned_model": {
                "text": fine_tuned_result,
                "model_name": COUNTRY_MODELS[country]["name"],
                "model_id": COUNTRY_MODELS[country]["model_id"],
                "language": COUNTRY_MODELS[country]["language"]
            } if fine_tuned_result and country in COUNTRY_MODELS else None,
            "country": country,
            "processing_time": f"{elapsed_time:.2f} seconds"
        }
        
        print("\n=== Response Data ===")
        print(f"Base Model Result: {base_result}")
        print(f"Fine-tuned Model Result: {fine_tuned_result}")
        print(f"Country: {country}")
        print(f"Total processing time: {elapsed_time:.2f} seconds")
        
        # Return with proper encoding
        return JSONResponse(
            content=jsonable_encoder(response_data),
            headers={"Content-Type": "application/json; charset=utf-8"}
        )

    except Exception as e:
        print(f"\nError in transcribe_audio: {str(e)}")
        import traceback
        traceback.print_exc()
        return {"error": str(e)}

async def transcribe_with_fine_tuned_model(file_path: str, country: str):
    try:
        if country not in model_handlers:
            print(f"No model handler found for country: {country}")
            return None
        
        handler = model_handlers[country]
        if handler is None:
            print(f"Model handler is None for country: {country}")
            return None
            
        result = await handler.transcribe(file_path)
        if result is None:
            print(f"Transcription failed for {country}")
            return None
            
        return result
        
    except Exception as e:
        print(f"Error in fine-tuned transcription: {str(e)}")
        import traceback
        traceback.print_exc()
        return None

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000, log_level="debug")
