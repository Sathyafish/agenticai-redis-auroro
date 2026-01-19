import os

import psycopg2
from psycopg2.extras import RealDictCursor

AURORA_HOST = os.getenv("AURORA_HOST", "localhost")
AURORA_PORT = int(os.getenv("AURORA_PORT", "5432"))
AURORA_DB = os.getenv("AURORA_DB", "agentic")
AURORA_USER = os.getenv("AURORA_USER", "appuser")
AURORA_PASSWORD = os.getenv("AURORA_PASSWORD", "password")

EMBED_DIM = int(os.getenv("EMBED_DIM", "384"))

DDL = f"""
-- Enable pgvector
CREATE EXTENSION IF NOT EXISTS vector;

CREATE TABLE IF NOT EXISTS agent_runs (
  run_id TEXT PRIMARY KEY,
  goal TEXT NOT NULL,
  created_at TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE IF NOT EXISTS agent_steps (
  id BIGSERIAL PRIMARY KEY,
  run_id TEXT NOT NULL REFERENCES agent_runs(run_id) ON DELETE CASCADE,
  step_num INT NOT NULL,
  step_text TEXT NOT NULL,
  status TEXT NOT NULL,
  result TEXT,
  updated_at TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_agent_steps_run ON agent_steps(run_id);

-- Semantic long-term memory (vector store)
CREATE TABLE IF NOT EXISTS semantic_memories (
  id BIGSERIAL PRIMARY KEY,
  run_id TEXT,
  source TEXT NOT NULL,
  content TEXT NOT NULL,
  embedding vector({EMBED_DIM}) NOT NULL,
  metadata JSONB DEFAULT '{{}}'::jsonb,
  created_at TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_semantic_memories_run_id ON semantic_memories(run_id);

-- Approximate nearest neighbor index (HNSW)
-- If your pgvector version doesn't support HNSW, change to ivfflat.
CREATE INDEX IF NOT EXISTS idx_semantic_memories_hnsw
  ON semantic_memories USING hnsw (embedding vector_cosine_ops);
"""


def get_conn():
    return psycopg2.connect(
        host=AURORA_HOST,
        port=AURORA_PORT,
        dbname=AURORA_DB,
        user=AURORA_USER,
        password=AURORA_PASSWORD,
        connect_timeout=5,
    )


def init_db():
    with get_conn() as conn:
        with conn.cursor() as cur:
            cur.execute(DDL)
        conn.commit()


def insert_run(run_id: str, goal: str):
    with get_conn() as conn:
        with conn.cursor() as cur:
            cur.execute(
                "INSERT INTO agent_runs(run_id, goal) VALUES(%s, %s) ON CONFLICT DO NOTHING",
                (run_id, goal),
            )
        conn.commit()


def insert_step(run_id: str, step_num: int, step_text: str, status: str):
    with get_conn() as conn:
        with conn.cursor() as cur:
            cur.execute(
                "INSERT INTO agent_steps(run_id, step_num, step_text, status) VALUES(%s, %s, %s, %s)",
                (run_id, step_num, step_text, status),
            )
        conn.commit()


def update_step(run_id: str, step_num: int, status: str, result: str | None):
    with get_conn() as conn:
        with conn.cursor() as cur:
            cur.execute(
                """
                UPDATE agent_steps
                SET status=%s, result=%s, updated_at=now()
                WHERE run_id=%s AND step_num=%s
                """,
                (status, result, run_id, step_num),
            )
        conn.commit()


def fetch_run(run_id: str):
    with get_conn() as conn:
        with conn.cursor(cursor_factory=RealDictCursor) as cur:
            cur.execute("SELECT * FROM agent_runs WHERE run_id=%s", (run_id,))
            run = cur.fetchone()
            cur.execute("SELECT * FROM agent_steps WHERE run_id=%s ORDER BY step_num", (run_id,))
            steps = cur.fetchall()
            return {"run": run, "steps": steps}
