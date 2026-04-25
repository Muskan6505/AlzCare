"""
python-ai-pipeline/utils/llm.py
Gemini-powered response generation with grounded, emotion-aware prompts.
"""
from __future__ import annotations

import os
import re

import google.generativeai as genai
from loguru import logger

_gemini_model = None


def load_llm() -> None:
    global _gemini_model

    api_key = os.getenv("GEMINI_API_KEY")

    if not api_key:
        logger.warning("GEMINI_API_KEY not found. Using fallback only.")
        return

    try:
        getattr(genai, "configure")(api_key=api_key)
        _gemini_model = genai.GenerativeModel("models/gemini-2.5-flash")
        logger.info("Gemini initialized")
    except Exception as exc:
        logger.error(f"Gemini init failed: {exc}")
        _gemini_model = None


def _format_memory_context(long_term_memories: list[dict]) -> str:
    lines = []
    for memory in long_term_memories:
        content = " ".join(str(memory.get("content", "")).split())
        if not content:
            continue
        tags = memory.get("tags") or ["memory"]
        score = memory.get("score")
        score_text = f" score={score:.3f}" if isinstance(score, (float, int)) else ""
        lines.append(f"- [{tags[0]}]{score_text} {content}")
    return "\n".join(lines) or "- none"


def _format_note_context(caregiver_notes: list[dict]) -> str:
    lines = []
    for note in caregiver_notes:
        text = " ".join(str(note.get("note", "")).split())
        if not text:
            continue
        score = note.get("score")
        score_text = f" score={score:.3f}" if isinstance(score, (float, int)) else ""
        lines.append(f"- [caregiver-note]{score_text} {text}")
    return "\n".join(lines) or "- none"


def _style_instruction_for_emotion(emotion: str, patient_name: str) -> str:
    if emotion in ("Agitated", "Fear"):
        return (
            f"{patient_name} sounds distressed. Reassure safety first. "
            "Use calm, grounding language and one simple next step."
        )
    if emotion == "Sad":
        return (
            f"{patient_name} sounds sad. Acknowledge the feeling warmly and respond with gentle comfort."
        )
    if emotion == "Happy":
        return (
            f"{patient_name} sounds positive. Match the warmth, but still keep the reply simple and clear."
        )
    return "Keep the tone soft, steady, and easy to understand."


def _clean_response(text: str) -> str:
    cleaned = " ".join(text.replace("\n", " ").split())
    cleaned = cleaned.strip(" \"'")
    cleaned = re.sub(r"\s+([,.!?])", r"\1", cleaned)

    sentence_matches = re.findall(r"[^.!?]+[.!?]?", cleaned)
    sentences = [segment.strip() for segment in sentence_matches if segment.strip()]
    if len(sentences) > 2:
        cleaned = " ".join(sentences[:2]).strip()

    if cleaned and cleaned[-1] not in ".!?":
        cleaned += "."
    return cleaned


def generate_reply(
    transcript: str,
    emotion: str,
    long_term_memories: list[dict],
    caregiver_notes: list[dict],
    patient_name: str = "friend",
) -> str:
    memory_context = _format_memory_context(long_term_memories)
    note_context = _format_note_context(caregiver_notes)
    emotion_style = _style_instruction_for_emotion(emotion, patient_name)

    prompt = f"""
You are a compassionate voice assistant for an Alzheimer's patient named {patient_name}.

Write a soft, natural spoken reply that sounds human and calming.

Rules:
- Use at most 2 short sentences.
- Use simple words.
- Respect the patient's current emotion.
- Use retrieved memories or caregiver notes only if they are directly relevant to what the patient said.
- If the retrieved context seems unrelated or weak, ignore it.
- Do not invent facts.
- Do not mention databases, notes, tags, scores, or "retrieved memories".
- If the patient sounds confused or afraid, reassure first and orient gently.

Patient mood: {emotion}
Style guidance: {emotion_style}

Patient said:
"{transcript}"

Relevant long-term memories:
{memory_context}

Relevant caregiver notes:
{note_context}

Return only the reply text.
"""

    if _gemini_model:
        try:
            response = _gemini_model.generate_content(
                prompt,
                generation_config={
                    "temperature": 0.45,
                    "max_output_tokens": 90,
                },
            )
            text = _extract_text(response)
            if text:
                cleaned = _clean_response(text)
                if cleaned:
                    return cleaned
        except Exception as exc:
            logger.error(f"Gemini failed: {exc}")

    fallbacks = {
        "Agitated": f"It's okay, {patient_name}. You're safe with me, so let's take one slow breath together.",
        "Fear": f"You're safe, {patient_name}. I'm here with you, and we can take this one step at a time.",
        "Sad": f"I hear you, {patient_name}. I'm here with you, and you are not alone.",
        "Neutral": f"I'm here with you, {patient_name}. Tell me what you need.",
        "Happy": f"That sounds nice, {patient_name}. Tell me a little more.",
    }
    return fallbacks.get(emotion, f"I'm here with you, {patient_name}.")


def _extract_text(response) -> str | None:
    try:
        if hasattr(response, "text") and response.text:
            return response.text

        if hasattr(response, "candidates"):
            for candidate in response.candidates:
                parts = getattr(candidate.content, "parts", [])
                for part in parts:
                    if hasattr(part, "text") and part.text:
                        return part.text
    except Exception as exc:
        logger.warning(f"Response parsing failed: {exc}")

    return None
