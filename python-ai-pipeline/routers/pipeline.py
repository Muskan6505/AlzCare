from __future__ import annotations

import asyncio
import io
import re
from datetime import datetime
from typing import Any, Optional

import httpx
from fastapi import APIRouter, File, Form, HTTPException, UploadFile
from fastapi.responses import StreamingResponse
from loguru import logger
from pydantic import BaseModel

from utils.config import (
    CONTEXT_SCORE_MARGIN,
    LLM_TIMEOUT_SECONDS,
    MAX_CONTEXT_MEMORIES,
    MAX_CONTEXT_NOTES,
    MEMORY_MIN_SCORE,
    NODE_BACKEND_URL,
    NOTE_MIN_SCORE,
    TOP_K_MEMORIES,
    TOP_K_NOTES,
)
from utils.distress_analyser import analyse_audio
from utils.embedder import embed
from utils.emotion import classify_emotion, is_distressed
from utils.llm import generate_reply
from utils.stt import transcribe
from utils.tts import synthesise

router = APIRouter(tags=["AI Pipeline"])

_tts_cache: dict[str, bytes] = {}
_TTS_TIMEOUT_SECONDS = 20
# Hard wall for LLM — faster than config default so UI feels snappy
_LLM_HARD_TIMEOUT = min(LLM_TIMEOUT_SECONDS, 30)


# ── Pydantic schemas ──────────────────────────────────────────────────────────
class MultimodalResponse(BaseModel):
    patient_id:      str
    transcript:      str
    emotion:         str
    distress_flag:   bool
    prosodic_state:  str
    llm_reply:       str
    audio_url:       str
    distress_log_id: Optional[str] = None


class ReminderRequest(BaseModel):
    patient_id: str
    task:       str


class EmbedStoreRequest(BaseModel):
    patient_id: str
    collection: str
    content:    str
    tags:       list[str] = []
    note:       str = ""


class TtsSpeakRequest(BaseModel):
    text:    str
    emotion: str = "Neutral"


# ── Node backend helpers ──────────────────────────────────────────────────────
async def _call_node(method: str, path: str, payload: dict) -> Any:
    url = f"{NODE_BACKEND_URL}{path}"
    try:
        async with httpx.AsyncClient(timeout=6.0) as client:
            if method == "POST":
                resp = await client.post(url, json=payload)
            else:
                resp = await client.get(url, params=payload)
            if resp.status_code < 300:
                return resp.json()
            logger.warning(f"Node {resp.status_code} [{method} {path}]: {resp.text[:120]}")
            return {}
    except Exception as exc:
        logger.warning(f"Node call failed [{method} {path}]: {exc}")
        return {}


def _fallback_reply(transcript: str, emotion: str, patient_name: str) -> str:
    text = transcript.lower()
    if "time" in text:
        now = datetime.now().strftime("%I:%M %p").lstrip("0")
        return f"It's {now}, {patient_name}. I'm right here with you."
    if emotion in ("Agitated", "Fear"):
        return f"You're safe, {patient_name}. Take a slow breath with me."
    if emotion == "Sad":
        return f"I hear you, {patient_name}. You're not alone. I'm with you."
    return f"I'm here with you, {patient_name}. Tell me a little more."


def _normalise_text(text: str) -> str:
    return " ".join(text.lower().strip().split())


def _tokenize(text: str) -> set[str]:
    return {
        token for token in re.findall(r"[a-z0-9']+", _normalise_text(text))
        if len(token) > 2
    }


def _overlap_ratio(query_tokens: set[str], candidate_text: str) -> float:
    if not query_tokens:
        return 0.0
    candidate_tokens = _tokenize(candidate_text)
    if not candidate_tokens:
        return 0.0
    return len(query_tokens & candidate_tokens) / len(query_tokens)


def _filter_context_items(
    items: list[dict],
    transcript: str,
    *,
    text_key: str,
    min_score: float,
    score_margin: float,
    max_items: int,
) -> list[dict]:
    if not items:
        return []

    query_tokens = _tokenize(transcript)
    best_score = max(
        (float(item.get("score", 0.0)) for item in items if isinstance(item.get("score"), (float, int))),
        default=0.0,
    )

    kept: list[dict] = []
    for item in items:
        text_value = str(item.get(text_key, "")).strip()
        if not text_value:
            continue

        vector_score = float(item.get("score", 0.0) or 0.0)
        keyword_overlap = _overlap_ratio(query_tokens, text_value)
        near_best = best_score > 0 and (best_score - vector_score) <= score_margin
        good_overlap = keyword_overlap >= 0.2
        good_vector = vector_score >= min_score

        if good_vector or (near_best and good_overlap):
            enriched = dict(item)
            enriched["keyword_overlap"] = round(keyword_overlap, 3)
            enriched["relevance"] = round(vector_score + (keyword_overlap * 0.1), 3)
            kept.append(enriched)

    kept.sort(key=lambda item: (item.get("relevance", 0.0), item.get("score", 0.0)), reverse=True)
    return kept[:max_items]


# ── Expanded fast-path detection ──────────────────────────────────────────────
_FAST_PATTERNS: dict[str, list[str]] = {
    "reminder": [
        "reminder", "reminders", "what do i need to do", "what should i do now",
        "what do i do now", "need to do now", "anything i need to do",
        "what's next", "what is next",
    ],
    "time": [
        "what time", "tell me the time", "time now", "current time",
        "what's the time", "what is the time",
    ],
    "greeting": [
        "hello", "hi there", "good morning", "good afternoon",
        "good evening", "hey", "how are you",
    ],
    "yes": ["yes", "yeah", "yep", "done", "ok", "okay", "finished", "i did it", "all done"],
    "no":  ["no", "not yet", "haven't done", "i haven't", "not done"],
}


def _detect_fast_intent(transcript: str) -> Optional[str]:
    text = _normalise_text(transcript)
    for intent, phrases in _FAST_PATTERNS.items():
        if any(phrase in text for phrase in phrases):
            return intent
    return None


def _is_reminder_active_today(reminder: dict, now: datetime) -> bool:
    status = reminder.get("status", "pending")
    if status not in {"pending", "escalated"}:
        return False
    frequency = reminder.get("frequency", "daily")
    weekday = now.weekday()
    if frequency == "weekdays" and weekday >= 5:
        return False
    if frequency == "weekends" and weekday < 5:
        return False
    return True


def _minutes_until(reminder_time: str, now: datetime) -> Optional[int]:
    try:
        hour, minute = [int(p) for p in reminder_time.split(":", 1)]
    except Exception:
        return None
    reminder_dt = now.replace(hour=hour, minute=minute, second=0, microsecond=0)
    return int((reminder_dt - now).total_seconds() // 60)


def _build_reminder_reply(reminders: list[dict], patient_name: str, now: datetime) -> str:
    active = [r for r in reminders if _is_reminder_active_today(r, now)]
    if not active:
        return f"You don't have any active reminders right now, {patient_name}."

    enriched = [(r, _minutes_until(r.get("time", ""), now)) for r in active]
    due_now = [r for r, d in enriched if d is not None and -15 <= d <= 15]
    if due_now:
        task = due_now[0].get("task", "your reminder")
        return f"Yes, {patient_name}. Right now you need to {task}."
    upcoming = sorted([(r, d) for r, d in enriched if d is not None and d > 15], key=lambda x: x[1])
    if upcoming:
        r, _ = upcoming[0]
        return f"Your next reminder is at {r.get('time','later')}, {patient_name}. You need to {r.get('task','complete your task')}."
    return f"You have reminders saved, {patient_name}, but I'm not sure about the next time."


async def _build_fast_reply(intent: str, patient_id: str, patient_name: str, transcript: str) -> str:
    now = datetime.now()
    if intent == "time":
        return f"It's {now.strftime('%I:%M %p').lstrip('0')}, {patient_name}."
    if intent == "reminder":
        reminders = await _call_node("GET", "/api/reminders", {"patient_id": patient_id})
        if isinstance(reminders, list):
            return _build_reminder_reply(reminders, patient_name, now)
        return f"I couldn't check your reminders right now, {patient_name}."
    if intent == "greeting":
        hour = now.hour
        time_of_day = "morning" if hour < 12 else "afternoon" if hour < 18 else "evening"
        return f"Good {time_of_day}, {patient_name}! It's great to hear from you. How are you feeling?"
    if intent == "yes":
        return f"Wonderful, {patient_name}! I'm proud of you. Is there anything else I can help you with?"
    if intent == "no":
        return f"That's okay, {patient_name}. Whenever you're ready, I'll be right here with you."
    return f"I'm here with you, {patient_name}."


async def _run_blocking_with_timeout(func, *args, timeout: int):
    loop = asyncio.get_event_loop()
    return await asyncio.wait_for(
        loop.run_in_executor(None, func, *args),
        timeout=timeout,
    )


async def _dual_rag(embedding: list[float], patient_id: str) -> tuple[list, list]:
    memories_task = _call_node("POST", "/api/memories/search", {
        "embedding": embedding,
        "patient_id": patient_id,
        "topK": TOP_K_MEMORIES,
        "minScore": MEMORY_MIN_SCORE,
    })
    notes_task = _call_node("POST", "/api/notes/search", {
        "embedding": embedding,
        "patient_id": patient_id,
        "topK": TOP_K_NOTES,
        "minScore": NOTE_MIN_SCORE,
    })
    # Run both RAG searches in parallel
    memories_resp, notes_resp = await asyncio.gather(memories_task, notes_task)
    return memories_resp.get("memories", []), notes_resp.get("notes", [])


async def _log_distress(payload: dict) -> Optional[str]:
    resp = await _call_node("POST", "/api/distress", payload)
    return resp.get("id")


# ── Endpoints ─────────────────────────────────────────────────────────────────
@router.post("/process-multimodal", response_model=MultimodalResponse)
async def process_multimodal(
    audio:      UploadFile = File(...),
    patient_id: str        = Form(...),
):
    wav_bytes = await audio.read()
    loop      = asyncio.get_event_loop()

    # 1. STT (always needed)
    transcript = await loop.run_in_executor(None, transcribe, wav_bytes)
    logger.info(f"[{patient_id}] Transcript: {transcript!r}")

    # Fetch profile (lightweight)
    profile      = await _call_node("GET", f"/api/patients/{patient_id}", {})
    patient_name = profile.get("name", "friend")

    # ── Fast path: skip LLM + RAG entirely ──────────────────────────────────
    fast_intent = _detect_fast_intent(transcript)
    if fast_intent is not None:
        llm_reply = await _build_fast_reply(fast_intent, patient_id, patient_name, transcript)
        logger.info(f"[{patient_id}] Fast [{fast_intent}] → {llm_reply!r}")

        # TTS runs concurrently; even if it times out, return immediately
        try:
            audio_bytes = await _run_blocking_with_timeout(
                synthesise, llm_reply, "Neutral", timeout=_TTS_TIMEOUT_SECONDS,
            )
        except Exception as exc:
            logger.warning(f"[{patient_id}] Fast TTS failed: {exc}")
            audio_bytes = b""
        _tts_cache[patient_id] = audio_bytes

        return MultimodalResponse(
            patient_id=patient_id,
            transcript=transcript,
            emotion="Neutral",
            distress_flag=False,
            prosodic_state="fast_path",
            llm_reply=llm_reply,
            audio_url=f"/tts-audio/{patient_id}" if audio_bytes else "",
            distress_log_id=None,
        )

    # ── Full pipeline ────────────────────────────────────────────────────────

    # 2. Emotion + Prosodic in parallel (saves ~0.5–1 s vs sequential)
    try:
        emotion_task  = loop.run_in_executor(None, classify_emotion, wav_bytes)
        prosodic_task = loop.run_in_executor(None, analyse_audio, wav_bytes)
        emotion, prosodic = await asyncio.gather(emotion_task, prosodic_task)
    except Exception as exc:
        logger.warning(f"[{patient_id}] Emotion/prosodic parallel failed: {exc}")
        emotion  = "Neutral"
        prosodic = {"pitch_variance": 0, "silence_ratio": 0, "prosodic_state": "normal"}

    logger.info(f"[{patient_id}] Emotion={emotion} Prosodic={prosodic['prosodic_state']}")

    # 3. Embed + dual RAG in parallel
    try:
        embedding = await loop.run_in_executor(None, embed, transcript)
        long_memories, notes = await _dual_rag(embedding, patient_id)
        long_memories = _filter_context_items(
            long_memories,
            transcript,
            text_key="content",
            min_score=MEMORY_MIN_SCORE,
            score_margin=CONTEXT_SCORE_MARGIN,
            max_items=MAX_CONTEXT_MEMORIES,
        )
        notes = _filter_context_items(
            notes,
            transcript,
            text_key="note",
            min_score=NOTE_MIN_SCORE,
            score_margin=CONTEXT_SCORE_MARGIN,
            max_items=MAX_CONTEXT_NOTES,
        )
    except Exception as exc:
        logger.warning(f"[{patient_id}] Embed/RAG failed: {exc}")
        embedding, long_memories, notes = [], [], []

    logger.info(f"[{patient_id}] RAG → {len(long_memories)} memories, {len(notes)} notes")
    if long_memories:
        logger.info(
            f"[{patient_id}] Memory context: "
            + " | ".join(
                f"{m.get('score', 0.0):.3f}:{str(m.get('content', ''))[:90]}"
                for m in long_memories
            )
        )
    if notes:
        logger.info(
            f"[{patient_id}] Note context: "
            + " | ".join(
                f"{n.get('score', 0.0):.3f}:{str(n.get('note', ''))[:90]}"
                for n in notes
            )
        )

    # 4. LLM (with hard timeout for snappy responses)
    try:
        llm_reply = await _run_blocking_with_timeout(
            generate_reply,
            transcript, emotion, long_memories, notes, patient_name,
            timeout=_LLM_HARD_TIMEOUT,
        )
    except Exception as exc:
        logger.warning(f"[{patient_id}] LLM fallback ({exc.__class__.__name__}): {exc}")
        llm_reply = _fallback_reply(transcript, emotion, patient_name)
    logger.info(f"[{patient_id}] LLM: {llm_reply!r}")

    # 5. TTS (non-blocking failure)
    try:
        audio_bytes = await _run_blocking_with_timeout(
            synthesise, llm_reply, emotion, timeout=_TTS_TIMEOUT_SECONDS,
        )
    except Exception as exc:
        logger.warning(f"[{patient_id}] TTS failed: {exc}")
        audio_bytes = b""
    _tts_cache[patient_id] = audio_bytes

    # 6. Distress log + alert (fire-and-forget; don't block response)
    distress_flag = is_distressed(emotion)
    async def _log_and_alert():
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
        if distress_flag:
            await _call_node("POST", "/api/alerts/agitation", {
                "patient_id": patient_id, "emotion": emotion,
                "transcript": transcript, "logId": log_id,
                "timestamp": datetime.utcnow().isoformat(),
            })
        return log_id

    # Schedule logging in background; return response immediately
    log_task = asyncio.create_task(_log_and_alert())

    return MultimodalResponse(
        patient_id=patient_id,
        transcript=transcript,
        emotion=emotion,
        distress_flag=distress_flag,
        prosodic_state=prosodic["prosodic_state"],
        llm_reply=llm_reply,
        audio_url=f"/tts-audio/{patient_id}" if audio_bytes else "",
        distress_log_id=None,  # logged in background
    )


@router.get("/tts-audio/{patient_id}")
async def get_tts_audio(patient_id: str):
    audio = _tts_cache.get(patient_id, b"")
    if not audio:
        raise HTTPException(404, "No audio cached for this patient.")
    return StreamingResponse(
        io.BytesIO(audio), media_type="audio/wav",
        headers={"Content-Disposition": f"inline; filename={patient_id}_reply.wav"},
    )


@router.post("/generate-reminder")
async def generate_reminder(body: ReminderRequest):
    loop = asyncio.get_event_loop()
    profile      = await _call_node("GET", f"/api/patients/{body.patient_id}", {})
    patient_name = profile.get("name", "friend")

    text = (
        f"Hello {patient_name}! A gentle reminder — "
        f"it's time to {body.task}. "
        "Whenever you're ready, just let me know you've done it."
    )

    # Generate TTS in background so the HTTP response is instant
    async def _bg_tts():
        audio_bytes = await loop.run_in_executor(None, synthesise, text, "Neutral")
        _tts_cache[f"reminder_{body.patient_id}"] = audio_bytes

    asyncio.create_task(_bg_tts())

    return {
        "patient_id":    body.patient_id,
        "reminder_text": text,
        "audio_url":     f"/tts-audio/reminder_{body.patient_id}",
    }


@router.post("/embed-and-store", status_code=201)
async def embed_and_store(body: EmbedStoreRequest):
    loop      = asyncio.get_event_loop()
    embedding = await loop.run_in_executor(None, embed, body.content or body.note)
    if body.collection == "memories":
        resp = await _call_node("POST", "/api/memories", {
            "patient_id": body.patient_id, "content": body.content,
            "embedding": embedding, "tags": body.tags,
        })
    else:
        resp = await _call_node("POST", "/api/notes", {
            "patient_id": body.patient_id, "note": body.note or body.content,
            "embedding": embedding,
        })
    return {"id": resp.get("id"), "embedded": True}


@router.post("/tts-speak")
async def tts_speak(body: TtsSpeakRequest):
    loop        = asyncio.get_event_loop()
    audio_bytes = await loop.run_in_executor(None, synthesise, body.text, body.emotion)
    if not audio_bytes:
        raise HTTPException(500, "TTS synthesis failed.")
    return StreamingResponse(
        io.BytesIO(audio_bytes), media_type="audio/wav",
        headers={"Content-Disposition": "inline; filename=announcement.wav"},
    )
