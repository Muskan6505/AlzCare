"""
python-ai-pipeline/utils/llm.py
Gemini-powered response generation (fast) + rule-based fallback
"""
from __future__ import annotations
import os
from loguru import logger
import google.generativeai as genai

_gemini_model = None


# ============================================================
# INIT GEMINI
# ============================================================
def load_llm() -> None:
    global _gemini_model

    api_key = os.getenv("GEMINI_API_KEY")

    if not api_key:
        logger.warning("GEMINI_API_KEY not found. Using fallback only.")
        return

    try:
        # Safe configure (avoids Pylance warning)
        getattr(genai, "configure")(api_key=api_key)

        # ✅ BEST MODEL (fast + stable)
        _gemini_model = genai.GenerativeModel("models/gemini-2.5-flash")

        logger.info("Gemini initialized ✅")

    except Exception as e:
        logger.error(f"Gemini init failed: {e}")
        _gemini_model = None


# ============================================================
# GENERATE REPLY
# ============================================================
def generate_reply(
    transcript: str,
    emotion: str,
    long_term_memories: list[dict],
    caregiver_notes: list[dict],
    patient_name: str = "friend",
) -> str:

    # =========================
    # 🔹 Build context
    # =========================
    mem_ctx = "\n".join(
        f"  • [{m.get('tags', ['memory'])[0]}] {m.get('content', '')}"
        for m in long_term_memories
    ) or "  (No long-term memories retrieved)"

    note_ctx = "\n".join(
        f"  • [today's note] {n.get('note', '')}"
        for n in caregiver_notes
    ) or "  (No caregiver notes for today)"

    # =========================
    # 🔹 Emotion prefix
    # =========================
    distress_prefix = ""
    if emotion in ("Agitated", "Fear"):
        distress_prefix = f"It's okay, {patient_name}. I'm right here with you. "
    elif emotion == "Sad":
        distress_prefix = f"I hear you, {patient_name}. You're not alone. "

    # =========================
    # 🔹 Prompt
    # =========================
    prompt = f"""
You are a warm, gentle assistant for {patient_name}, who has Alzheimer's.
Speak simply, kindly, and in very short sentences (1-3 sentences max).

Long-term memories:
{mem_ctx}

Today's caregiver notes:
{note_ctx}

Patient said: "{transcript}"
Emotion: {emotion}

{distress_prefix}
Respond gently and simply.
"""

    # ============================================================
    # 🚀 GEMINI (PRIMARY)
    # ============================================================
    if _gemini_model:
        try:
            response = _gemini_model.generate_content(
                prompt,
                generation_config={
                    "temperature": 0.6,
                    "max_output_tokens": 100,
                }
            )

            text = _extract_text(response)

            if text:
                return text.strip()

        except Exception as e:
            logger.error(f"Gemini failed: {e}")

    # ============================================================
    # 🛟 RULE-BASED FALLBACK
    # ============================================================
    fallbacks = {
        "Agitated": f"It's okay, {patient_name}. I'm right here with you. Take a slow breath.",
        "Fear":     f"You're safe, {patient_name}. I'm here and everything is alright.",
        "Sad":      f"I hear you, {patient_name}. You're not alone — I'm with you.",
        "Neutral":  f"I understand, {patient_name}. How can I help you today?",
        "Happy":    f"That's wonderful, {patient_name}! Tell me more!",
    }

    return fallbacks.get(emotion, f"I'm here with you, {patient_name}.")


# ============================================================
# 🔧 SAFE RESPONSE PARSER
# ============================================================
def _extract_text(response) -> str | None:
    try:
        if hasattr(response, "text") and response.text:
            return response.text

        if hasattr(response, "candidates"):
            for c in response.candidates:
                parts = getattr(c.content, "parts", [])
                for p in parts:
                    if hasattr(p, "text"):
                        return p.text
    except Exception as e:
        logger.warning(f"Response parsing failed: {e}")

    return None