from fastapi import FastAPI, UploadFile, File, Form, WebSocket, WebSocketDisconnect, Body
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse, FileResponse, StreamingResponse
from fastapi.encoders import jsonable_encoder
from faster_whisper import WhisperModel
from transformers import WhisperForConditionalGeneration, WhisperProcessor, pipeline
import tempfile
import os
import torch
import asyncio
from pathlib import Path
import librosa
from transformers.models.whisper import tokenization_whisper
import time
from pydub import AudioSegment
import soundfile as sf
import numpy as np
import noisereduce as nr
import subprocess
from starlette.background import BackgroundTask
import shutil

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
        "type": "malaysian",
        "use_faster_whisper": True  # Enable faster-whisper for this model
    },
    "Singapore": {
        "name": "Singlish Whisper Model",
        "model_id": "jensenlwt/whisper-small-singlish-122k",
        "language": "en",
        "type": "pipeline",
        "use_faster_whisper": True  # Enable faster-whisper for this model
    },
    "Thailand": {
        "name": "Thai Whisper Model",
        "model_id": "juierror/whisper-tiny-thai",
        "language": "th",
        "type": "thai",
        "use_faster_whisper": True  # Enable faster-whisper for this model
    }
}

# Configure pytorch settings
if torch.cuda.is_available():
    print("CUDA available - using GPU acceleration")
    torch.backends.cuda.matmul.allow_tf32 = True
    torch.backends.cudnn.allow_tf32 = True
    TORCH_DTYPE = torch.float16
else:
    print("CUDA not available - using CPU")
    TORCH_DTYPE = torch.float32

class FasterWhisperHandler:
    """Handle faster-whisper models for specific countries/languages"""
    
    def __init__(self, model_config, cache_dir):
        self.config = model_config
        self.cache_dir = cache_dir
        self.model = None
        self.device = "cuda" if torch.cuda.is_available() else "cpu"
        self.compute_type = "float16" if self.device == "cuda" else "int8"
        print(f"Using device: {self.device} for model: {model_config['name']}")
        
    async def load(self):
        """Initialize the faster-whisper model"""
        try:
            model_id = self.config["model_id"]
            self.model = WhisperModel(
                "small",
                device=self.device,
                compute_type=self.compute_type,
                download_root=str(self.cache_dir)
            )
            print(f"Faster-Whisper model loaded successfully for {self.config['name']}")
            return True
        except Exception as e:
            print(f"Error loading Faster-Whisper model: {str(e)}")
            import traceback
            traceback.print_exc()
            return False
    
    async def transcribe(self, file_path: str) -> str:
        """Transcribe audio using faster-whisper"""
        try:
            language = self.config["language"]
            print(f"Transcribing with Faster-Whisper model for {language}")
            segments, info = await asyncio.to_thread(
                self.model.transcribe,
                file_path,
                beam_size=5,
                language=language,
                task="transcribe",
                vad_filter=True,
                initial_prompt=f"This is {language} speech."
            )
            transcript = " ".join(segment.text for segment in segments)
            print(f"Faster-Whisper transcription complete: {transcript}")
            print(f"Detected language: {info.language} with probability {info.language_probability:.2f}")
            return transcript
        except Exception as e:
            print(f"Error in Faster-Whisper transcription: {str(e)}")
            import traceback
            traceback.print_exc()
            return None

class ModelHandler:
    def __init__(self, model_config, cache_dir):
        self.config = model_config
        self.cache_dir = cache_dir
        self.model = None
        self.processor = None
        self.pipeline = None
        self.device = "cuda" if torch.cuda.is_available() else "cpu"
        print(f"Using device: {self.device} for model: {model_config['name']}")

    async def load(self):
        try:
            model_type = self.config["type"]
            model_id = self.config["model_id"]
            if model_type == "pipeline":
                print(f"Loading pipeline model: {model_id}")
                try:
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
            else:
                print(f"Loading custom model: {model_id}")
                processor_kwargs = {"cache_dir": self.cache_dir}
                if model_type != "malaysian":
                    processor_kwargs["language"] = self.config["language"]
                    processor_kwargs["task"] = "transcribe"
                self.processor = WhisperProcessor.from_pretrained(
                    model_id, **processor_kwargs
                )
                dtype = torch.float16 if self.device == "cuda" else torch.float32
                self.model = WhisperForConditionalGeneration.from_pretrained(
                    model_id,
                    cache_dir=self.cache_dir,
                    torch_dtype=dtype
                ).to(self.device)
                self.model.eval()
                print(f"Custom model loaded successfully on {self.device}")
            return True
        except Exception as e:
            print(f"Error loading model {model_id}: {str(e)}")
            import traceback
            traceback.print_exc()
            return False
            
    async def transcribe(self, file_path: str) -> str:
        """Unified transcription method for all model types"""
        try:
            model_type = self.config["type"]
            if model_type == "pipeline":
                print("Using pipeline transcription")
                result = await asyncio.to_thread(
                    self.pipeline, 
                    file_path
                )
                transcription = result["text"]
                print(f"Pipeline transcription: {transcription}")
                return transcription
            print(f"Transcribing with custom model type: {model_type}")
            audio, sr = await asyncio.to_thread(librosa.load, file_path, sr=16000, mono=True)
            print(f"Loaded audio: {len(audio)} samples, {sr}Hz")
            inputs = self.processor(audio, sampling_rate=16000, return_tensors="pt")
            input_features = inputs.input_features.to(self.device)
            generation_kwargs = {}
            if model_type == "malaysian":
                generation_kwargs["language"] = "ms" 
            elif model_type == "thai":
                generation_kwargs["language"] = "th"
                generation_kwargs["max_new_tokens"] = 255
            else:
                generation_kwargs["language"] = self.config["language"]
            generation_kwargs["task"] = "transcribe"
            use_amp = self.device == "cuda"
            with torch.no_grad():
                if use_amp:
                    with torch.cuda.amp.autocast():
                        generated = await asyncio.to_thread(
                            self.model.generate,
                            input_features,
                            **generation_kwargs
                        )
                else:
                    generated = await asyncio.to_thread(
                        self.model.generate,
                        input_features,
                        **generation_kwargs
                    )
            transcription = self.processor.batch_decode(
                generated, 
                skip_special_tokens=True
            )[0]
            print(f"{model_type.capitalize()} model transcription: {transcription}")
            return transcription
        except Exception as e:
            print(f"Error in {self.config['name']} transcription: {str(e)}")
            import traceback
            traceback.print_exc()
            return None

# Initialize model handlers
model_handlers = {}

async def initialize_models():
    """Initialize all models asynchronously"""
    print("Initializing models...")
    device = "cuda" if torch.cuda.is_available() else "cpu"
    compute_type = "float16" if device == "cuda" else "int8"
    print(f"Using device: {device}, compute type: {compute_type}")
    print("Loading base Whisper model...")
    global base_model
    try:
        model_path = str(PROJECT_ROOT / "models" / "whisper")
        print(f"Loading faster-whisper model from: {model_path}")
        print(f"Model directory exists: {os.path.exists(model_path)}")
        print(f"Model directory contents: {os.listdir(model_path) if os.path.exists(model_path) else 'Directory does not exist'}")
        base_model = WhisperModel(
            "tiny", 
            device=device,
            compute_type=compute_type,
            download_root=str(PROJECT_ROOT / "models" / "whisper")
        )
        print("Base model loaded successfully")
    except Exception as e:
        print(f"Error loading base model: {str(e)}")
        raise RuntimeError("Failed to load base Whisper model")
    for country, config in COUNTRY_MODELS.items():
        model_specific_cache = MODEL_CACHE_DIR / config["model_id"].replace('/', '_')
        if config.get("use_faster_whisper", False):
            handler = FasterWhisperHandler(config, model_specific_cache)
        else:
            handler = ModelHandler(config, model_specific_cache)
        await handler.load()
        model_handlers[country] = handler
    print("Model initialization complete")

def optimize_gpu_memory():
    """Configure PyTorch for optimal GPU memory usage"""
    if torch.cuda.is_available():
        torch.cuda.empty_cache()
        try:
            import gc
            gc.collect()
        except Exception as e:
            print(f"Could not optimize GPU memory: {str(e)}")

@app.on_event("startup")
async def startup_event():
    """Initialize models when the FastAPI app starts"""
    optimize_gpu_memory()
    await initialize_models()

async def transcribe_with_base_model(file_path: str):
    """Transcribe audio using the faster-whisper model"""
    try:
        print("Starting base model transcription...")
        segments, info = await asyncio.to_thread(
            base_model.transcribe,
            file_path,
            beam_size=5,
            language="en",
            task="transcribe",
            vad_filter=True,
        )
        transcript = " ".join(segment.text for segment in segments)
        print(f"Base model transcription complete: {transcript}")
        print(f"Detected language: {info.language} with probability {info.language_probability:.2f}")
        return transcript
    except Exception as e:
        print(f"Error in base model transcription: {str(e)}")
        import traceback
        traceback.print_exc()
        return "Base model transcription failed"

@app.post("/transcribe/")
async def transcribe_audio(
    file: UploadFile = File(...),
    country: str = Form(None)
):
    try:
        print("\n=== Received Request ===")
        print(f"Country: '{country}'")
        start_time = time.time()
        with tempfile.NamedTemporaryFile(delete=False, suffix='.m4a') as temp_file:
            content = await file.read()
            temp_file.write(content)
            temp_path = temp_file.name
            print(f"File saved at: {temp_path}")
        print("Starting denoising process...")
        denoiser = AudioDenoiser(sample_rate=48000)
        denoised_result = await denoiser.process_audio(temp_path)
        denoised_path = denoised_result["output_path"]
        print(f"Audio denoised. Starting transcription...")
        print(f"Noise reduction metrics: {denoised_result['metrics']}")
        print("Starting parallel transcription...")
        base_task = asyncio.create_task(transcribe_with_base_model(denoised_path))
        fine_tuned_task = asyncio.create_task(
            transcribe_with_fine_tuned_model(denoised_path, country)
        ) if country in COUNTRY_MODELS else None
        if fine_tuned_task:
            base_result, fine_tuned_result = await asyncio.gather(base_task, fine_tuned_task)
        else:
            base_result = await base_task
            fine_tuned_result = None
        for path in [temp_path, denoised_path]:
            if path and os.path.exists(path):
                os.unlink(path)
                print(f"Removed temporary file: {path}")
        elapsed_time = time.time() - start_time
        response_data = {
            "base_model": {
                "text": base_result,
                "model": "faster-whisper-tiny"
            },
            "fine_tuned_model": {
                "text": fine_tuned_result,
                "model_name": COUNTRY_MODELS[country]["name"],
                "model_id": COUNTRY_MODELS[country]["model_id"],
                "language": COUNTRY_MODELS[country]["language"],
                "using_faster_whisper": COUNTRY_MODELS[country].get("use_faster_whisper", False)
            } if fine_tuned_result and country in COUNTRY_MODELS else None,
            "country": country,
            "processing_time": f"{elapsed_time:.2f} seconds",
            "noise_reduction_metrics": denoised_result["metrics"],
            "backend": "faster-whisper"
        }
        print("\n=== Response Data ===")
        print(f"Base Model Result: {base_result}")
        print(f"Fine-tuned Model Result: {fine_tuned_result}")
        print(f"Country: {country}")
        print(f"Total processing time: {elapsed_time:.2f} seconds")
        return JSONResponse(
            content=jsonable_encoder(response_data),
            headers={"Content-Type": "application/json; charset=utf-8"}
        )
    except Exception as e:
        print(f"\nError in transcribe_audio: {str(e)}")
        import traceback
        traceback.print_exc()
        if 'temp_path' in locals() and temp_path and os.path.exists(temp_path):
            os.unlink(temp_path)
        if 'denoised_path' in locals() and denoised_path and os.path.exists(denoised_path):
            os.unlink(denoised_path)
        return JSONResponse(
            status_code=500,
            content={"error": str(e)}
        )

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

class AudioDenoiser:
    def __init__(self, sample_rate: int = 48000, chunk_size_seconds: float = 5.0):
        self.sample_rate = sample_rate
        self.chunk_size_seconds = chunk_size_seconds
        print(f"Noise reduction initialized with {sample_rate}Hz sample rate, {chunk_size_seconds}s chunks")

# Replace the entire audio denoiser process_audio method with this corrected version
async def process_audio(self, file_path: str, output_format: str = 'wav') -> dict:
    try:
        print("\n=== Starting Audio Processing ===")
        print(f"Input file: {file_path}")
        
        # Create output folder if needed
        temp_dir = os.path.dirname(file_path)
        output_path = os.path.join(temp_dir, f'denoised_{os.path.basename(file_path)}')
        
        # Convert to WAV if needed
        wav_path = file_path
        if not file_path.lower().endswith('.wav'):
            wav_path = file_path + ".wav"
            print(f"Converting to WAV format: {wav_path}")
            result = subprocess.run([
                'ffmpeg',
                '-i', file_path,
                '-acodec', 'pcm_s16le',
                '-ar', str(self.sample_rate),
                '-ac', '1',
                '-y',
                wav_path
            ], capture_output=True, text=True)
            
            if result.returncode != 0:
                raise Exception(f"FFmpeg conversion failed: {result.stderr}")
        
        # Read audio info
        with sf.SoundFile(wav_path) as sound_file:
            total_frames = len(sound_file)
            sample_rate = sound_file.samplerate
            channels = sound_file.channels
        
        print(f"Audio info: {total_frames} frames, {sample_rate}Hz, {channels} channels")
        chunk_size_frames = int(self.chunk_size_seconds * sample_rate)
        print(f"Processing in chunks of {chunk_size_frames} frames ({self.chunk_size_seconds}s)")
        
        output_path = wav_path.replace('.wav', '_denoised.wav')
        total_original_energy = 0
        total_denoised_energy = 0
        num_samples = 0
        
        # Get noise profile from first part of audio
        noise_profile_frames = min(int(0.5 * sample_rate), total_frames)
        with sf.SoundFile(wav_path) as infile:
            noise_profile = infile.read(noise_profile_frames, dtype='float32')
            if channels > 1:
                noise_profile = noise_profile.mean(axis=1)
        
        # Process audio in chunks
        with sf.SoundFile(wav_path) as infile, sf.SoundFile(
            output_path, 'w', samplerate=sample_rate, channels=1, format='WAV',
            subtype='PCM_16'
        ) as outfile:
            infile.seek(0)
            processed_frames = 0
            while processed_frames < total_frames:
                chunk_size = min(chunk_size_frames, total_frames - processed_frames)
                audio_chunk = infile.read(chunk_size, dtype='float32')
                if channels > 1:
                    audio_chunk = audio_chunk.mean(axis=1)
                
                chunk_original_energy = np.sum(audio_chunk ** 2)
                total_original_energy += chunk_original_energy
                num_samples += len(audio_chunk)
                
                print(f"Processing chunk {processed_frames}-{processed_frames + len(audio_chunk)}...")
                denoised_chunk = await asyncio.to_thread(
                    nr.reduce_noise,
                    y=audio_chunk,
                    sr=sample_rate,
                    y_noise=noise_profile if processed_frames == 0 else None,
                    stationary=True,
                    prop_decrease=0.75,
                    freq_mask_smooth_hz=100,
                    n_jobs=1
                )
                
                chunk_denoised_energy = np.sum(denoised_chunk ** 2)
                total_denoised_energy += chunk_denoised_energy
                outfile.write(denoised_chunk)
                processed_frames += len(audio_chunk)
                print(f"Progress: {processed_frames}/{total_frames} frames " 
                      f"({processed_frames/total_frames*100:.1f}%)")
        
        # Calculate metrics
        if num_samples > 0:
            original_rms = np.sqrt(total_original_energy / num_samples)
            denoised_rms = np.sqrt(total_denoised_energy / num_samples)
            noise_reduction = original_rms - denoised_rms
        else:
            original_rms = denoised_rms = noise_reduction = 0
            
        print("\n=== Processing Complete ===")
        print(f"Saved to: {output_path}")
        print(f"Original RMS: {original_rms:.4f}")
        print(f"Denoised RMS: {denoised_rms:.4f}")
        print(f"Noise Reduction: {noise_reduction:.4f}")
        
        # Cleanup original WAV if it was converted
        if wav_path != file_path and os.path.exists(wav_path):
            os.unlink(wav_path)
            
        return {
            "output_path": output_path,
            "metrics": {
                "original_rms": float(original_rms),
                "denoised_rms": float(denoised_rms),
                "noise_reduction": float(noise_reduction)
            }
        }
        
    except Exception as e:
        print(f"Error in audio processing: {str(e)}")
        import traceback
        traceback.print_exc()
        
        # Cleanup
        if 'wav_path' in locals() and wav_path != file_path and os.path.exists(wav_path):
            try:
                os.unlink(wav_path)
            except:
                pass
        
        raise
    
@app.post("/denoise/")
async def denoise_audio(file: UploadFile = File(...)):
    temp_path = None
    wav_path = None
    denoised_path = None
    try:
        print("\n=== Received Audio File ===")
        print(f"Filename: {file.filename}")
        print(f"Content type: {file.content_type}")
        temp_dir = tempfile.mkdtemp()
        print(f"Created temp directory: {temp_dir}")
        temp_path = os.path.join(temp_dir, 'input.m4a')
        content = await file.read()
        with open(temp_path, 'wb') as f:
            f.write(content)
        print(f"Saved original file: {temp_path}")
        wav_path = os.path.join(temp_dir, 'converted.wav')
        print("Converting to WAV...")
        result = subprocess.run([
            'ffmpeg',
            '-i', temp_path,
            '-acodec', 'pcm_s16le',
            '-ar', '48000',
            '-ac', '1',
            '-y',
            wav_path
        ], capture_output=True, text=True)
        if result.returncode != 0:
            raise Exception(f"FFmpeg conversion failed: {result.stderr}")
        denoiser = AudioDenoiser(sample_rate=48000, chunk_size_seconds=2.0)
        result = await denoiser.process_audio(wav_path)
        denoised_path = result["output_path"]
        if not os.path.exists(denoised_path):
            raise Exception("Denoising failed to create output file")
        response = FileResponse(
            denoised_path,
            media_type='audio/wav',
            headers={
                "X-Original-RMS": str(result["metrics"]["original_rms"]),
                "X-Denoised-RMS": str(result["metrics"]["denoised_rms"]),
                "X-Noise-Reduction": str(result["metrics"]["noise_reduction"])
            }
        )
        def cleanup():
            try:
                for path in [temp_path, wav_path, denoised_path]:
                    if path and os.path.exists(path):
                        os.unlink(path)
                if os.path.exists(temp_dir):
                    os.rmdir(temp_dir)
                print("Cleanup completed")
            except Exception as e:
                print(f"Cleanup error: {e}")
        response.background = BackgroundTask(cleanup)
        return response
    except Exception as e:
        print(f"Error processing request: {str(e)}")
        import traceback
        traceback.print_exc()
        try:
            for path in [temp_path, wav_path, denoised_path]:
                if path and os.path.exists(path):
                    os.unlink(path)
            if 'temp_dir' in locals() and os.path.exists(temp_dir):
                os.rmdir(temp_dir)
        except Exception as cleanup_error:
            print(f"Cleanup error: {cleanup_error}")
        return JSONResponse(
            status_code=500,
            content={"error": str(e)}
        )

@app.get("/system-info/")
async def system_info():
    """Get information about the system and GPU"""
    import platform
    info = {
        "system": {
            "platform": platform.platform(),
            "python_version": platform.python_version(),
            "torch_version": torch.__version__,
            "faster_whisper": True
        },
        "gpu": {
            "available": torch.cuda.is_available(),
        }
    }
    if torch.cuda.is_available():
        device_count = torch.cuda.device_count()
        info["gpu"]["count"] = device_count
        info["gpu"]["devices"] = []
        for i in range(device_count):
            info["gpu"]["devices"].append({
                "name": torch.cuda.get_device_name(i),
                "memory_total_MB": round(torch.cuda.get_device_properties(i).total_memory / (1024 * 1024)),
                "memory_allocated_MB": round(torch.cuda.memory_allocated(i) / (1024 * 1024)),
                "memory_reserved_MB": round(torch.cuda.memory_reserved(i) / (1024 * 1024))
            })
    return info

@app.post("/transcribe_chunk/")
async def transcribe_chunk(
    file: UploadFile = File(...), 
    streaming: bool = Form(False),
    country: str = Form(None)
):
    """Transcribe a single audio chunk for streaming recognition"""
    try:
        content = await file.read()
        print(f"Received chunk from {country}, size: {len(content)} bytes")
        
        # Check if content is valid
        if len(content) < 44:  # Minimum WAV header size
            return {"error": "Audio chunk too small", "partial_transcript": ""}
        
        # Create a temp dir to work in
        temp_dir = tempfile.mkdtemp()
        try:
            # Save the content as is to a temp file
            temp_chunk_path = os.path.join(temp_dir, "chunk.wav")
            with open(temp_chunk_path, "wb") as f:
                f.write(content)
                
            print(f"Saved chunk to: {temp_chunk_path}")
            
            # Skip denoising for now to debug the file format issue
            # Just try to transcribe directly
            try:
                if country and country in model_handlers:
                    transcript = await model_handlers[country].transcribe(temp_chunk_path)
                else:
                    segments, info = await asyncio.to_thread(
                        base_model.transcribe,
                        temp_chunk_path,
                        beam_size=1,
                        language="en",
                        task="transcribe",
                        vad_filter=True
                    )
                    transcript = " ".join(segment.text for segment in segments)
                
                print(f"Successfully transcribed chunk: '{transcript}'")
                return {
                    "partial_transcript": transcript,
                    "denoising_metrics": {"original_rms": 0, "denoised_rms": 0, "noise_reduction": 0}
                }
            except Exception as transcribe_error:
                print(f"Transcription failed, trying wav conversion: {transcribe_error}")
                
                # If direct transcription fails, try converting to WAV first
                fixed_wav_path = os.path.join(temp_dir, "fixed.wav")
                result = subprocess.run([
                    'ffmpeg',
                    '-i', temp_chunk_path,
                    '-acodec', 'pcm_s16le',
                    '-ar', '16000',
                    '-ac', '1',
                    '-y',
                    fixed_wav_path
                ], capture_output=True, text=True)
                
                if result.returncode == 0:
                    print("Converted to WAV format successfully")
                    # Now try transcription on the converted file
                    if country and country in model_handlers:
                        transcript = await model_handlers[country].transcribe(fixed_wav_path)
                    else:
                        segments, info = await asyncio.to_thread(
                            base_model.transcribe,
                            fixed_wav_path,
                            beam_size=1,
                            language="en",
                            task="transcribe",
                            vad_filter=True
                        )
                        transcript = " ".join(segment.text for segment in segments)
                    
                    print(f"Successfully transcribed converted chunk: '{transcript}'")
                    return {
                        "partial_transcript": transcript,
                        "denoising_metrics": {"original_rms": 0, "denoised_rms": 0, "noise_reduction": 0}
                    }
                else:
                    raise Exception(f"FFmpeg conversion failed: {result.stderr}")
                
        finally:
            # Clean up temp files
            try:
                shutil.rmtree(temp_dir)
            except Exception as e:
                print(f"Error cleaning up temp dir: {e}")
                
    except Exception as e:
        print(f"Error transcribing chunk: {str(e)}")
        import traceback
        traceback.print_exc()
        return {"error": str(e), "partial_transcript": ""}

@app.post("/echo_test/")
async def echo_test(file: UploadFile = File(...)):
    content = await file.read()
    size = len(content)
    return {"received_bytes": size, "status": "ok"}

@app.post("/upload/")
async def upload_and_process_audio(
    file: UploadFile = File(...),
    country: str = Form(None)
):
    """Process uploaded audio: denoise and transcribe in one endpoint"""
    temp_path = None
    denoised_path = None
    try:
        print("\n=== Received Audio Upload ===")
        print(f"Country context: {country}")
        start_time = time.time()
        
        # Save uploaded file
        temp_dir = tempfile.mkdtemp()
        temp_path = os.path.join(temp_dir, 'input.wav')
        content = await file.read()
        with open(temp_path, 'wb') as f:
            f.write(content)
        print(f"Saved audio file ({len(content)/1024:.2f} KB) to: {temp_path}")
        
        # Step 1: Denoise the audio
        print("Starting audio denoising...")
        denoiser = AudioDenoiser(sample_rate=16000, chunk_size_seconds=0.5)
        denoised_result = await denoiser.process_audio(temp_path)
        denoised_path = denoised_result["output_path"]
        print(f"Audio denoised: {denoised_path}")
        
        # Step 2: Transcribe with appropriate model
        print("Starting transcription...")
        base_task = asyncio.create_task(transcribe_with_base_model(denoised_path))
        fine_tuned_task = asyncio.create_task(
            transcribe_with_fine_tuned_model(denoised_path, country)
        ) if country in model_handlers else None
        
        if fine_tuned_task:
            base_result, fine_tuned_result = await asyncio.gather(base_task, fine_tuned_task)
        else:
            base_result = await base_task
            fine_tuned_result = None
        
        # Generate response
        elapsed_time = time.time() - start_time
        print(f"\n=== Processing complete in {elapsed_time:.2f} seconds ===")
        
        response_data = {
            "base_model": {
                "text": base_result,
                "model": "faster-whisper-tiny"
            },
            "fine_tuned_model": {
                "text": fine_tuned_result,
                "model_name": COUNTRY_MODELS[country]["name"] if country in COUNTRY_MODELS else None,
                "model_id": COUNTRY_MODELS[country]["model_id"] if country in COUNTRY_MODELS else None
            } if fine_tuned_result else None,
            "country": country,
            "processing_time": f"{elapsed_time:.2f} seconds",
            "denoising_metrics": denoised_result["metrics"]
        }
        
        print("Base model result:", base_result)
        print("Fine-tuned model result:", fine_tuned_result)
        
        # Clean up temp files
        for path in [temp_path, denoised_path]:
            if path and os.path.exists(path):
                os.unlink(path)
                print(f"Removed temporary file: {path}")
        if os.path.exists(temp_dir):
            shutil.rmtree(temp_dir)
        
        return JSONResponse(
            content=jsonable_encoder(response_data),
            headers={"Content-Type": "application/json; charset=utf-8"}
        )
        
    except Exception as e:
        print(f"\nError in upload_and_process_audio: {str(e)}")
        import traceback
        traceback.print_exc()
        
        # Clean up any temp files
        try:
            for path in [temp_path, denoised_path]:
                if path and os.path.exists(path):
                    os.unlink(path)
            if 'temp_dir' in locals() and os.path.exists(temp_dir):
                shutil.rmtree(temp_dir)
        except Exception as cleanup_error:
            print(f"Cleanup error: {cleanup_error}")
            
        return JSONResponse(
            status_code=500,
            content={"error": str(e)}
        )
    
if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000, log_level="debug")

