"""
python-ai-pipeline/utils/tts.py
Azure Cognitive Services TTS — emotion-adaptive SSML.
  • Distressed (Agitated/Fear/Sad) → style='whispering', rate='-25%', pitch='+5%'
  • Normal/Happy                   → style='hopeful',    rate='-15%', pitch='+5%'
Voice: en-US-JennyNeural (available in East US, West Europe, and more)
"""
from __future__ import annotations
import azure.cognitiveservices.speech as speechsdk
from loguru import logger
from utils.config import AZURE_SPEECH_KEY, AZURE_SPEECH_REGION

_DISTRESSED_EMOTIONS = {"Agitated", "Fear", "Sad"}


def _build_ssml(text: str, emotion: str) -> str:
    """Generate Alzheimer's-friendly SSML based on detected emotion."""
    if emotion in _DISTRESSED_EMOTIONS:
        style = "whispering"
        rate  = "-25%"
        pitch = "+5%"
    else:
        style = "hopeful"
        rate  = "-15%"
        pitch = "+5%"

    safe = (text.replace("&", "&amp;").replace("<", "&lt;")
                .replace(">", "&gt;").replace('"', "&quot;").replace("'", "&apos;"))

    return (
        "<speak version='1.0' "
        "xmlns='http://www.w3.org/2001/10/synthesis' "
        "xmlns:mstts='http://www.w3.org/2001/mstts' "
        "xml:lang='en-US'>"
        "<voice name='en-US-JennyNeural'>"
        f"<mstts:express-as style='{style}'>"
        f"<prosody rate='{rate}' pitch='{pitch}'>{safe}</prosody>"
        "</mstts:express-as>"
        "</voice></speak>"
    )


def synthesise(text: str, emotion: str = "Neutral") -> bytes:
    """Synthesise text → raw WAV bytes (16 kHz, 16-bit mono PCM)."""
    cfg = speechsdk.SpeechConfig(subscription=AZURE_SPEECH_KEY, region=AZURE_SPEECH_REGION)
    cfg.set_speech_synthesis_output_format(
        speechsdk.SpeechSynthesisOutputFormat.Riff16Khz16BitMonoPcm
    )
    stream       = speechsdk.audio.PullAudioOutputStream()
    audio_cfg    = speechsdk.audio.AudioOutputConfig(stream=stream)
    synthesiser  = speechsdk.SpeechSynthesizer(speech_config=cfg, audio_config=audio_cfg)

    result = synthesiser.speak_ssml_async(_build_ssml(text, emotion)).get()
    if result.reason == speechsdk.ResultReason.SynthesizingAudioCompleted:
        logger.info(f"TTS done  [emotion={emotion}] ✅")
        return result.audio_data
    details = result.cancellation_details
    logger.error(f"TTS failed: {details.reason} — {details.error_details}")
    return b""
