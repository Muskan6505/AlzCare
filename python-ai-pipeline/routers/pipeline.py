"""
python-ai-pipeline/routers/pipeline.py

POST /process-multimodal
  ├── faster-whisper  → transcript
  ├── Wav2Vec2        → emotion label
  ├── librosa         → prosodic features
  ├── MiniLM embed    → vector
  ├── Node RAG        → dual-source (Patient_Memories + Caregiver_Notes)
  ├── ctransformers   → LLM reply
  └── Azure TTS SSML  → WAV audio

POST /generate-reminder
  Called by Node.js reminder worker for personalised reminder voice.

POST /embed-and-store
  Embed any text and forward to Node for MongoDB storage.

POST /tts-speak
  Raw TTS for arbitrary text (reminder engine, system messages).
"""
from __future__ import annotations

import asyncio
import io
from datetime import datetime
from typing import Optional

import httpx
from fastapi import APIRouter, File, Form, HTTPException, UploadFile
from fastapi.responses import StreamingResponse
from loguru import logger
from pydantic import BaseModel

from utils.config import NODE_BACKEND_URL, TOP_K_MEMORIES, TOP_K_NOTES
from utils.distress_analyser import analyse_audio
from utils.embedder import embed
from utils.emotion import classify_emotion, is_distressed
from utils.llm import generate_reply
from utils.stt import transcribe
from utils.tts import synthesise

router = APIRouter(tags=["AI Pipeline"])

# In-process TTS audio cache (latest reply per patient_id)
_tts_cache: dict[str, bytes] = {}


# ── Pydantic schemas ──────────────────────────────────────────────────────────
class MultimodalResponse(BaseModel):
    patient_id:    str
    transcript:    str
    emotion:       str
    distress_flag: bool
    prosodic_state: str
    llm_reply:     str
    audio_url:     str
    distress_log_id: Optional[str] = None


class ReminderRequest(BaseModel):
    patient_id: str
    task:       str


class EmbedStoreRequest(BaseModel):
    patient_id: str
    collection: str       # "memories" | "notes"
    content:    str       # text to embed
    tags:       list[str] = []
    note:       str = ""  # for caregiver notes


class TtsSpeakRequest(BaseModel):
    text:    str
    emotion: str = "Neutral"


# ── Node backend helpers ──────────────────────────────────────────────────────
async def _call_node(method: str, path: str, payload: dict) -> dict:
    """Generic helper to POST/GET the Node.js backend."""
    url = f"{NODE_BACKEND_URL}{path}"
    try:
        async with httpx.AsyncClient(timeout=8.0) as client:
            if method == "POST":
                resp = await client.post(url, json=payload)
            else:
                resp = await client.get(url, params=payload)
            return resp.json() if resp.status_code < 300 else {}
    except Exception as exc:
        logger.warning(f"Node call failed [{method} {path}]: {exc}")
        return {}


async def _dual_rag(embedding: list[float], patient_id: str) -> tuple[list, list]:
    """
    Query Patient_Memories (long-term) AND Caregiver_Notes (short-term)
    in parallel via Node backend MongoDB Atlas Vector Search.
    """
    memories_task = _call_node("POST", "/api/memories/search", {
        "embedding": embedding, "patient_id": patient_id, "topK": TOP_K_MEMORIES
    })
    notes_task = _call_node("POST", "/api/notes/search", {
        "embedding": embedding, "patient_id": patient_id, "topK": TOP_K_NOTES
    })
    memories_resp, notes_resp = await asyncio.gather(memories_task, notes_task)
    return (
        memories_resp.get("memories", []),
        notes_resp.get("notes", []),
    )


async def _log_distress(payload: dict) -> Optional[str]:
    resp = await _call_node("POST", "/api/distress", payload)
    return resp.get("id")


# ── Endpoints ─────────────────────────────────────────────────────────────────

@router.post("/process-multimodal", response_model=MultimodalResponse)
async def process_multimodal(
    audio:      UploadFile = File(...),
    patient_id: str        = Form(...),
):
    """
    Full multimodal pipeline for every patient voice interaction.
    Accepts WAV audio + patient_id form fields.
    """
    wav_bytes  = await audio.read()
    loop       = asyncio.get_event_loop()

    # 1. Whisper STT (faster-whisper, CPU int8)
    transcript = await loop.run_in_executor(None, transcribe, wav_bytes)
    logger.info(f"[{patient_id}] Transcript: {transcript!r}")

    # 2. Wav2Vec2 emotion classification
    emotion = await loop.run_in_executor(None, classify_emotion, wav_bytes)
    logger.info(f"[{patient_id}] Emotion: {emotion}")

    # 3. Librosa prosodic analysis (for logging + fallback distress)
    prosodic = await loop.run_in_executor(None, analyse_audio, wav_bytes)

    # 4. Embed transcript → dual-source RAG
    embedding          = await loop.run_in_executor(None, embed, transcript)
    long_memories, notes = await _dual_rag(embedding, patient_id)
    logger.info(f"[{patient_id}] RAG → {len(long_memories)} memories, {len(notes)} notes")

    # 5. Fetch patient name from Node backend
    profile = await _call_node("GET", f"/api/patients/{patient_id}", {})
    patient_name = profile.get("name", "friend")

    # 6. LLM reply (dual-context)
    llm_reply = await loop.run_in_executor(
        None, generate_reply, transcript, emotion, long_memories, notes, patient_name
    )
    logger.info(f"[{patient_id}] LLM: {llm_reply!r}")

    # 7. Azure TTS (emotion-adaptive SSML)
    audio_bytes = await loop.run_in_executor(None, synthesise, llm_reply, emotion)
    _tts_cache[patient_id] = audio_bytes

    # 8. Persist distress log
    distress_flag = is_distressed(emotion)
    log_id = await _log_distress({
        "patient_id":    patient_id,
        "timestamp":     datetime.utcnow().isoformat(),
        "transcript":    transcript,
        "emotion":       emotion,
        "distressFlag":  distress_flag,
        "pitchVariance": prosodic["pitch_variance"],
        "silenceRatio":  prosodic["silence_ratio"],
        "prosodicState": prosodic["prosodic_state"],
    })

    # 9. Alert Node if high agitation
    if distress_flag:
        logger.warning(f"[{patient_id}] DISTRESS — forwarding alert to Node")
        await _call_node("POST", "/api/alerts/agitation", {
            "patient_id":  patient_id,
            "emotion":     emotion,
            "transcript":  transcript,
            "logId":       log_id,
            "timestamp":   datetime.utcnow().isoformat(),
        })

    return MultimodalResponse(
        patient_id=patient_id,
        transcript=transcript,
        emotion=emotion,
        distress_flag=distress_flag,
        prosodic_state=prosodic["prosodic_state"],
        llm_reply=llm_reply,
        audio_url=f"/tts-audio/{patient_id}",
        distress_log_id=log_id,
    )


@router.get("/tts-audio/{patient_id}")
async def get_tts_audio(patient_id: str):
    """Serve the latest synthesised WAV for a patient."""
    audio = _tts_cache.get(patient_id, b"")
    if not audio:
        raise HTTPException(404, "No audio cached for this patient.")
    return StreamingResponse(
        io.BytesIO(audio), media_type="audio/wav",
        headers={"Content-Disposition": f"inline; filename={patient_id}_reply.wav"},
    )


@router.post("/generate-reminder")
async def generate_reminder(body: ReminderRequest):
    """
    Called by Node.js reminder worker.
    Generates a personalised, gentle reminder using TTS.
    Returns audio as WAV bytes + reminder text.
    """
    loop = asyncio.get_event_loop()

    # Fetch patient name
    profile      = await _call_node("GET", f"/api/patients/{body.patient_id}", {})
    patient_name = profile.get("name", "friend")

    text = (
        f"Hello {patient_name}! A gentle reminder — "
        f"it's time to {body.task}. "
        "Whenever you're ready, just let me know you've done it."
    )

    audio_bytes = await loop.run_in_executor(None, synthesise, text, "Neutral")
    _tts_cache[f"reminder_{body.patient_id}"] = audio_bytes

    return {
        "patient_id": body.patient_id,
        "reminder_text": text,
        "audio_url": f"/tts-audio/reminder_{body.patient_id}",
    }


@router.post("/embed-and-store", status_code=201)
async def embed_and_store(body: EmbedStoreRequest):
    """
    Embed text and forward to Node.js backend for MongoDB storage.
    collection: 'memories' | 'notes'
    """
    loop      = asyncio.get_event_loop()
    embedding = await loop.run_in_executor(None, embed, body.content or body.note)

    if body.collection == "memories":
        resp = await _call_node("POST", "/api/memories", {
            "patient_id": body.patient_id,
            "content":    body.content,
            "embedding":  embedding,
            "tags":       body.tags,
        })
    else:
        resp = await _call_node("POST", "/api/notes", {
            "patient_id": body.patient_id,
            "note":       body.note or body.content,
            "embedding":  embedding,
        })

    return {"id": resp.get("id"), "embedded": True}


@router.post("/tts-speak")
async def tts_speak(body: TtsSpeakRequest):
    """Raw TTS endpoint — used by reminder engine for system announcements."""
    loop        = asyncio.get_event_loop()
    audio_bytes = await loop.run_in_executor(None, synthesise, body.text, body.emotion)
    if not audio_bytes:
        raise HTTPException(500, "TTS synthesis failed.")
    return StreamingResponse(
        io.BytesIO(audio_bytes), media_type="audio/wav",
        headers={"Content-Disposition": "inline; filename=announcement.wav"},
    )
