"""
python-ai-pipeline/utils/stt.py
Local speech-to-text using faster-whisper (CTranslate2 backend).
Faster than openai-whisper, zero cmake, pre-built wheels available for all platforms.
"""
from __future__ import annotations
import io, os, tempfile
from loguru import logger
from faster_whisper import WhisperModel
from utils.config import WHISPER_MODEL_SIZE

_model: WhisperModel | None = None


def load_whisper() -> None:
    global _model
    logger.info(f"Loading faster-whisper [{WHISPER_MODEL_SIZE}] (CPU, int8) …")
    _model = WhisperModel(WHISPER_MODEL_SIZE, device="cpu", compute_type="int8")
    logger.info("faster-whisper ready ✅")


def transcribe(wav_bytes: bytes, language: str = "en") -> str:
    if _model is None:
        raise RuntimeError("Whisper not loaded — call load_whisper() first.")
    with tempfile.NamedTemporaryFile(suffix=".wav", delete=False) as tmp:
        tmp.write(wav_bytes)
        tmp_path = tmp.name
    try:
        segments, _ = _model.transcribe(tmp_path, language=language, beam_size=5)
        text = " ".join(seg.text for seg in segments).strip()
        logger.debug(f"Transcript: {text!r}")
        return text or "[No speech detected]"
    finally:
        os.unlink(tmp_path)
