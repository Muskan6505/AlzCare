"""
python-ai-pipeline/utils/llm.py
Local Mistral/LLaMA inference via ctransformers (pre-built ctypes — no cmake).
"""
from __future__ import annotations
import os
from loguru import logger
from utils.config import (
    LLM_CONTEXT_LENGTH,
    LLM_MAX_NEW_TOKENS,
    LLM_MODEL_PATH,
    LLM_MODEL_TYPE,
)

_llm = None


def load_llm() -> None:
    global _llm
    if not os.path.exists(LLM_MODEL_PATH):
        logger.warning(f"LLM model not found at '{LLM_MODEL_PATH}'. Using rule-based fallback.")
        return
    from ctransformers import AutoModelForCausalLM
    logger.info(f"Loading LLM [{LLM_MODEL_TYPE}] …")
    _llm = AutoModelForCausalLM.from_pretrained(
        LLM_MODEL_PATH, model_type=LLM_MODEL_TYPE,
        context_length=LLM_CONTEXT_LENGTH, max_new_tokens=LLM_MAX_NEW_TOKENS,
        temperature=0.7, top_p=0.9, repetition_penalty=1.1,
        local_files_only=True,
    )
    logger.info("LLM ready ✅")


def generate_reply(
    transcript: str,
    emotion: str,
    long_term_memories: list[dict],
    caregiver_notes: list[dict],
    patient_name: str = "friend",
) -> str:
    """
    Build a dual-source RAG prompt combining long-term Patient_Memories
    and short-term Caregiver_Notes, then generate a compassionate reply.
    """
    mem_ctx = "\n".join(
        f"  • [{m.get('tags',['memory'])[0] if m.get('tags') else 'memory'}] {m.get('content','')}"
        for m in long_term_memories
    ) or "  (No long-term memories retrieved)"

    note_ctx = "\n".join(
        f"  • [today's note] {n.get('note','')}"
        for n in caregiver_notes
    ) or "  (No caregiver notes for today)"

    distress_prefix = ""
    if emotion in ("Agitated", "Fear"):
        distress_prefix = f"It's okay, {patient_name}. I'm right here with you. "
    elif emotion == "Sad":
        distress_prefix = f"I hear you, {patient_name}. You're not alone. "

    prompt = (
        f"<s>[INST] You are a warm, gentle assistant for {patient_name}, who has Alzheimer's.\n"
        "Speak simply, kindly, and in very short sentences (1-3 sentences max).\n\n"
        f"Long-term memories about {patient_name}:\n{mem_ctx}\n\n"
        f"Today's caregiver notes:\n{note_ctx}\n\n"
        f"{patient_name} just said: \"{transcript}\"\n"
        f"Detected emotion: {emotion}\n\n"
        f"{distress_prefix}Respond gently and simply: [/INST]"
    )

    if _llm is None:
        fallbacks = {
            "Agitated": f"It's okay, {patient_name}. I'm right here with you. Take a slow breath.",
            "Fear":     f"You're safe, {patient_name}. I'm here and everything is alright.",
            "Sad":      f"I hear you, {patient_name}. You're not alone — I'm with you.",
            "Neutral":  f"I understand, {patient_name}. How can I help you today?",
            "Happy":    f"That's wonderful, {patient_name}! Tell me more!",
        }
        return fallbacks.get(emotion, f"I'm here with you, {patient_name}.")

    return _llm(prompt).strip()
