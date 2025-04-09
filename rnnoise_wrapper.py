import ctypes
import numpy as np
from pydub import AudioSegment

# Load the RNNoise library
rnnoise_lib = ctypes.CDLL("./librnnoise.so")  # Use ".dll" on Windows

# Define functions
rnnoise_lib.rnnoise_process_frame.argtypes = [
    ctypes.c_void_p,  # state
    np.ctypeslib.ndpointer(dtype=np.float32, flags="C_CONTIGUOUS"),  # output
    np.ctypeslib.ndpointer(dtype=np.float32, flags="C_CONTIGUOUS")   # input
]
rnnoise_lib.rnnoise_create.restype = ctypes.c_void_p
rnnoise_lib.rnnoise_destroy.argtypes = [ctypes.c_void_p]

def denoise_audio(input_file: str, output_file: str):
    # Load audio (convert to 16kHz mono if needed)
    audio = AudioSegment.from_wav(input_file)
    audio = audio.set_frame_rate(16000).set_channels(1)
    samples = np.array(audio.get_array_of_samples(), dtype=np.float32) / 32768.0  # Normalize to [-1, 1]

    # Initialize RNNoise
    state = rnnoise_lib.rnnoise_create(None)
    out = np.zeros_like(samples, dtype=np.float32)

    # Process frames (RNNoise expects 480-sample frames)
    frame_size = 480
    for i in range(0, len(samples), frame_size):
        frame = samples[i:i+frame_size]
        if len(frame) < frame_size:
            frame = np.pad(frame, (0, frame_size - len(frame)))
        rnnoise_lib.rnnoise_process_frame(state, out[i:i+frame_size], frame)

    # Save output
    denoised_audio = AudioSegment(
        (out * 32767.0).astype(np.int16).tobytes(),
        frame_rate=16000,
        sample_width=2,
        channels=1
    )
    denoised_audio.export(output_file, format="wav")
    rnnoise_lib.rnnoise_destroy(state)