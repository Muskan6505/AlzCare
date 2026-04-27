"""
python-ai-pipeline/utils/llm.py
Now uses Gemini via Express API instead of local ctransformers model.
"""
from __future__ import annotations

import httpx
from loguru import logger
from typing import Any

from utils.config import NODE_BACKEND_URL


# ── Compatibility ─────────────────────────────────────────────
def load_llm() -> None:
    """Kept for compatibility — not used anymore."""
    logger.info("Gemini mode enabled → skipping local LLM load")


# ── Node backend helper (ASYNC) ───────────────────────────────
async def _call_node(method: str, path: str, payload: dict | None = None) -> Any:
    """Generic helper to POST/GET the Node.js backend."""
    url = f"{NODE_BACKEND_URL}{path}"

    try:
        async with httpx.AsyncClient(timeout=8.0) as client:
            if method.upper() == "POST":
                resp = await client.post(url, json=payload or {})
            else:
                resp = await client.get(url, params=payload or {})

            if resp.status_code < 300:
                return resp.json()

            logger.warning(
                f"Node call returned {resp.status_code} [{method} {path}]: {resp.text[:200]}"
            )
            return {}

    except Exception as exc:
        logger.warning(f"Node call failed [{method} {path}]: {exc}")
        return {}


# ── MAIN LLM FUNCTION (FIXED) ────────────────────────────────
async def generate_reply(
    transcript: str,
    emotion: str,
    long_term_memories: list[dict],
    caregiver_notes: list[dict],
    patient_name: str = "friend",
) -> str:
    """
    Build prompt and send to Gemini via Node backend.
    """

    # ── memory context ─────────────────────────────
    mem_ctx = "\n".join(
        f"  • [{m.get('tags', ['memory'])[0] if m.get('tags') else 'memory'}] {m.get('content', '')}"
        for m in long_term_memories
    ) or "  (No long-term memories retrieved)"

    # ── notes context ──────────────────────────────
    note_ctx = "\n".join(
        f"  • [today's note] {n.get('note', '')}"
        for n in caregiver_notes
    ) or "  (No caregiver notes for today)"

    # ── emotion prefix ─────────────────────────────
    distress_prefix = ""
    if emotion in ("Agitated", "Fear"):
        distress_prefix = f"It's okay, {patient_name}. I'm right here with you. "
    elif emotion == "Sad":
        distress_prefix = f"I hear you, {patient_name}. You're not alone. "

    # ── prompt ──────────────────────────────────────
    prompt = (
        f"You are a warm, gentle assistant for {patient_name}, who has Alzheimer's.\n"
        "Speak simply, kindly, and in very short sentences (1-3 sentences max).\n\n"
        f"Long-term memories:\n{mem_ctx}\n\n"
        f"Caregiver notes:\n{note_ctx}\n\n"
        f"Patient said: \"{transcript}\"\n"
        f"Emotion: {emotion}\n\n"
        f"{distress_prefix}"
        "Respond gently and simply."
    )

    payload = {
        "contents": [
            {
                "parts": [{"text": prompt}]
            }
        ]
    }

    try:
        # ✅ FIX: MUST await
        data = await _call_node("POST", "/api/gemini", payload=payload)

        # safe extraction (no crash even if structure changes)
        reply = (
            data.get("candidates", [{}])[0]
                .get("content", {})
                .get("parts", [{}])[0]
                .get("text", "")
        )

        if reply:
            return reply.strip()

        raise ValueError("Empty Gemini response")

    except Exception as e:
        logger.warning(f"Gemini API failed: {e}")

        # ── fallback responses ───────────────────────
        fallbacks = {
            "Agitated": f"It's okay, {patient_name}. I'm right here with you.",
            "Fear":     f"You're safe, {patient_name}. I'm here with you.",
            "Sad":      f"I hear you, {patient_name}. You're not alone.",
            "Neutral":  f"I'm here with you, {patient_name}.",
            "Happy":    f"That's wonderful, {patient_name}!",
        }

        return fallbacks.get(
            emotion,
            f"I'm here with you, {patient_name}."
        )