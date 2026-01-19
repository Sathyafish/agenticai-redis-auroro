from __future__ import annotations

import hashlib
import os
from typing import List

# Keep this in sync with semantic_memories.embedding vector(DIM)
EMBED_DIM = int(os.getenv("EMBED_DIM", "384"))


def embed_text(text: str) -> List[float]:
    """Deterministic demo embedding.

    This is NOT semantically strong. It exists to:
      1) create stable vectors from text
      2) exercise pgvector inserts + similarity search end-to-end

    Replace this with a real embedding model (Bedrock/OpenAI/etc.) for production.
    """

    buckets = [0.0] * EMBED_DIM
    tokens = [t for t in text.lower().split() if t]

    for t in tokens:
        h = hashlib.sha256(t.encode("utf-8")).digest()
        for i in range(0, 32, 2):
            idx = (h[i] << 8 | h[i + 1]) % EMBED_DIM
            buckets[idx] += 1.0

    norm = sum(x * x for x in buckets) ** 0.5 or 1.0
    return [x / norm for x in buckets]
