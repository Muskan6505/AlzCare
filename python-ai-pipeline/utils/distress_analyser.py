"""
python-ai-pipeline/utils/distress_analyser.py
Prosodic feature extraction (librosa) — supplementary to Wav2Vec2 emotion.
Provides pitch variance and silence ratio for logging and threshold alerts.
"""
from __future__ import annotations
import io
import numpy as np
import librosa
from utils.config import SILENCE_CONFUSED_THRESHOLD, PITCH_AGITATION_THRESHOLD


def analyse_audio(wav_bytes: bytes) -> dict:
    with io.BytesIO(wav_bytes) as buf:
        y, sr = librosa.load(buf, sr=16_000, mono=True)

    # Silence ratio
    intervals      = librosa.effects.split(y, top_db=25)
    voiced_samples = sum(int(e) - int(s) for s, e in intervals)
    silence_ratio  = 1.0 - (voiced_samples / max(len(y), 1))

    # Pitch variance via pYIN
    try:
        f0, voiced_flag, _ = librosa.pyin(
            y, fmin=librosa.note_to_hz("C2"), fmax=librosa.note_to_hz("C7"), sr=sr
        )
        valid_f0       = f0[voiced_flag] if voiced_flag is not None else np.array([])
        pitch_variance = float(np.var(valid_f0)) if len(valid_f0) > 1 else 0.0
    except Exception:
        pitch_variance = 0.0

    # Prosodic state
    if pitch_variance > PITCH_AGITATION_THRESHOLD:
        prosodic_state = "agitated"
    elif silence_ratio > SILENCE_CONFUSED_THRESHOLD:
        prosodic_state = "confused"
    else:
        prosodic_state = "normal"

    return {
        "silence_ratio":   round(float(silence_ratio),  4),
        "pitch_variance":  round(float(pitch_variance), 2),
        "prosodic_state":  prosodic_state,
    }
