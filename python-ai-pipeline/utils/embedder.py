"""python-ai-pipeline/utils/embedder.py — 384-dim MiniLM sentence embeddings"""
from __future__ import annotations
from typing import List
from loguru import logger
from sentence_transformers import SentenceTransformer
from utils.config import EMBEDDING_MODEL

_embedder: SentenceTransformer | None = None


def load_embedder() -> None:
    global _embedder
    logger.info(f"Loading SentenceTransformer [{EMBEDDING_MODEL}] …")
    _embedder = SentenceTransformer(EMBEDDING_MODEL)
    logger.info("Embedder ready ✅")


def embed(text: str) -> List[float]:
    if _embedder is None:
        raise RuntimeError("Embedder not loaded.")
    return _embedder.encode(text, normalize_embeddings=True).tolist()
