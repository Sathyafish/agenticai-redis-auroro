from __future__ import annotations

import json
import os
from typing import Any, Dict, List, Optional, Tuple

from services.common.db import get_conn

EMBED_DIM = int(os.getenv("EMBED_DIM", "384"))


def _to_vector_literal(vec: List[float]) -> str:
    # pgvector accepts: '[0.1, 0.2, ...]'
    if len(vec) != EMBED_DIM:
        raise ValueError(f"Embedding dim mismatch: got {len(vec)} expected {EMBED_DIM}")
    return "[" + ", ".join(f"{x:.6f}" for x in vec) + "]"


def insert_memory(
    *,
    run_id: Optional[str],
    source: str,
    content: str,
    embedding: List[float],
    metadata: Optional[Dict[str, Any]] = None,
) -> int:
    v = _to_vector_literal(embedding)
    md = metadata or {}
    with get_conn() as conn:
        with conn.cursor() as cur:
            cur.execute(
                """
                INSERT INTO semantic_memories(run_id, source, content, embedding, metadata)
                VALUES (%s, %s, %s, %s::vector, %s::jsonb)
                RETURNING id
                """,
                (run_id, source, content, v, json.dumps(md)),
            )
            new_id = cur.fetchone()[0]
        conn.commit()
    return int(new_id)


def semantic_search(
    *,
    query_embedding: List[float],
    top_k: int = 5,
    run_id: Optional[str] = None,
) -> List[Dict[str, Any]]:
    """Cosine distance search.

    Lower distance means more similar.

    Requires the HNSW/ivfflat index to be created with vector_cosine_ops.
    """

    qv = _to_vector_literal(query_embedding)

    base = """
      SELECT id, run_id, source, content, metadata, created_at,
             (embedding <=> %s::vector) AS distance
      FROM semantic_memories
    """

    if run_id:
        sql = base + " WHERE run_id = %s ORDER BY embedding <=> %s::vector LIMIT %s"
        params: Tuple[Any, ...] = (qv, run_id, qv, top_k)
    else:
        sql = base + " ORDER BY embedding <=> %s::vector LIMIT %s"
        params = (qv, qv, top_k)

    with get_conn() as conn:
        with conn.cursor() as cur:
            cur.execute(sql, params)
            rows = cur.fetchall()

    results: List[Dict[str, Any]] = []
    for r in rows:
        results.append(
            {
                "id": r[0],
                "run_id": r[1],
                "source": r[2],
                "content": r[3],
                "metadata": r[4],
                "created_at": r[5].isoformat() if r[5] else None,
                "distance": float(r[6]),
            }
        )
    return results
