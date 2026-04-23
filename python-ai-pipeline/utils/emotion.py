"""
python-ai-pipeline/utils/emotion.py
Emotion classification using Wav2Vec2 via HuggingFace pipeline.
Uses ONNX-compatible inference path — no CUDA, no cmake required.

Returns one of: Agitated | Fear | Sad | Neutral | Happy
"""
from __future__ import annotations
import io, tempfile, os
import numpy as np
import soundfile as sf
from loguru import logger

# HuggingFace pipeline (transformers) runs inference via torch CPU
from transformers import pipeline as hf_pipeline
from utils.config import EMOTION_MODEL

_classifier = None  # HuggingFace audio-classification pipeline

# Map raw model labels → canonical emotion labels
_LABEL_MAP: dict[str, str] = {
    "angry":    "Agitated",
    "disgust":  "Agitated",
    "fear":     "Fear",
    "sad":      "Sad",
    "sadness":  "Sad",
    "neutral":  "Neutral",
    "calm":     "Neutral",
    "happy":    "Happy",
    "happiness":"Happy",
    "surprised":"Neutral",
}


def load_emotion_model() -> None:
    global _classifier
    logger.info(f"Loading Wav2Vec2 emotion model [{EMOTION_MODEL}] …")
    _classifier = hf_pipeline(
        "audio-classification",
        model=EMOTION_MODEL,
        device=-1,          # CPU — no CUDA build needed
    )
    logger.info("Emotion model ready ✅")


def classify_emotion(wav_bytes: bytes) -> str:
    """
    Classify the emotion in raw WAV bytes.
    Returns canonical label: Agitated | Fear | Sad | Neutral | Happy
    Falls back to 'Neutral' on any error.
    """
    if _classifier is None:
        logger.warning("Emotion model not loaded — defaulting to Neutral")
        return "Neutral"

    try:
        # Write to temp file; HuggingFace pipeline accepts file paths
        with tempfile.NamedTemporaryFile(suffix=".wav", delete=False) as tmp:
            tmp.write(wav_bytes)
            tmp_path = tmp.name

        results = _classifier(tmp_path, top_k=1)
        os.unlink(tmp_path)

        raw_label = results[0]["label"].lower().strip()
        canonical = _LABEL_MAP.get(raw_label, "Neutral")
        logger.info(f"Emotion → raw='{raw_label}' → canonical='{canonical}'")
        return canonical
    except Exception as exc:
        logger.warning(f"Emotion classification failed: {exc} — defaulting to Neutral")
        return "Neutral"


def is_distressed(emotion: str) -> bool:
    """Return True when the patient needs extra-gentle care."""
    return emotion in ("Agitated", "Fear", "Sad")
