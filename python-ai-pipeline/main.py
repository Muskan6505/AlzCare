"""
python-ai-pipeline/main.py
AlzCare v2 — Python AI Micro-service Entry Point

Runs on port 8001.
Loads all AI models once at startup, then serves:
  POST /process-multimodal  → full Whisper + Wav2Vec2 + RAG + LLM + TTS pipeline
  POST /generate-reminder   → personalised reminder TTS (called by Node cron)
  POST /embed-and-store     → embed text → store via Node/MongoDB
  POST /tts-speak           → arbitrary TTS synthesis
  GET  /tts-audio/{id}      → serve cached WAV replies
  GET  /health              → liveness probe
"""
from contextlib import asynccontextmanager
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from loguru import logger

from utils.config import WHISPER_MODEL_SIZE
from utils.stt      import load_whisper
from utils.emotion  import load_emotion_model
from utils.embedder import load_embedder
from utils.llm      import load_llm
from routers.pipeline import router as pipeline_router


@asynccontextmanager
async def lifespan(app: FastAPI):
    logger.info("🚀  AlzCare Python AI Pipeline v2 starting …")
    load_whisper()          # faster-whisper (CTranslate2, CPU int8)
    load_emotion_model()    # Wav2Vec2 emotion classifier (HuggingFace, CPU)
    load_embedder()         # all-MiniLM-L6-v2 sentence transformer
    load_llm()              # ctransformers GGUF (no cmake)
    logger.info("✅  All AI models loaded — ready to serve.")
    yield
    logger.info("🛑  Python AI Pipeline shutting down.")


app = FastAPI(
    title="AlzCare Python AI Pipeline v2",
    description=(
        "Multimodal AI micro-service: "
        "faster-whisper STT | Wav2Vec2 emotion | dual-source RAG | "
        "ctransformers LLM | Azure TTS SSML"
    ),
    version="2.0.0",
    lifespan=lifespan,
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"], allow_methods=["*"], allow_headers=["*"],
)

app.include_router(pipeline_router)


@app.get("/health", tags=["System"])
async def health():
    return {"service": "python-ai-pipeline", "version": "2.0.0", "status": "ok"}


if __name__ == "__main__":
    import uvicorn
    uvicorn.run("main:app", host="0.0.0.0", port=8001, reload=False)
