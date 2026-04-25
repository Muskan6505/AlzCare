"""python-ai-pipeline/utils/config.py — Central config from .env"""
import os
from dotenv import load_dotenv

load_dotenv()

# Azure TTS
AZURE_SPEECH_KEY:    str = os.getenv("AZURE_SPEECH_KEY",    "<YOUR_AZURE_SPEECH_KEY>")
AZURE_SPEECH_REGION: str = os.getenv("AZURE_SPEECH_REGION", "eastus")

# LLM
LLM_MODEL_PATH: str = os.getenv("LLM_MODEL_PATH", "./gguf_models/mistral-7b-instruct-v0.2.Q4_K_M.gguf")
LLM_MODEL_TYPE: str = os.getenv("LLM_MODEL_TYPE", "mistral")
LLM_CONTEXT_LENGTH: int = int(os.getenv("LLM_CONTEXT_LENGTH", "1024"))
LLM_MAX_NEW_TOKENS: int = int(os.getenv("LLM_MAX_NEW_TOKENS", "96"))
LLM_TIMEOUT_SECONDS: int = int(os.getenv("LLM_TIMEOUT_SECONDS", "60"))

# Emotion model (Wav2Vec2 via HuggingFace / ONNX)
EMOTION_MODEL: str = os.getenv("EMOTION_MODEL", "ehcalabres/wav2vec2-lg-xlsr-en-speech-emotion-recognition")

# Whisper
WHISPER_MODEL_SIZE: str = os.getenv("WHISPER_MODEL_SIZE", "base")

# Node.js backend
NODE_BACKEND_URL: str = os.getenv("NODE_BACKEND_URL", "http://localhost:4000")

# RAG
TOP_K_MEMORIES: int = int(os.getenv("TOP_K_MEMORIES", "3"))
TOP_K_NOTES:    int = int(os.getenv("TOP_K_NOTES",    "2"))

# Distress thresholds
PITCH_AGITATION_THRESHOLD:  float = float(os.getenv("PITCH_AGITATION_THRESHOLD",  "600.0"))
SILENCE_CONFUSED_THRESHOLD: float = float(os.getenv("SILENCE_CONFUSED_THRESHOLD", "0.40"))

# Embedding
EMBEDDING_MODEL: str = "all-MiniLM-L6-v2"
EMBEDDING_DIM:   int = 384
