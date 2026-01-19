import uuid

from fastapi import FastAPI

from services.common.db import fetch_run, init_db, insert_run, insert_step
from services.common.embeddings import embed_text
from services.common.memory import ShortTermMemory
from services.common.models import RunStatusResponse, SearchResponse, StartRunRequest, StartRunResponse
from services.common.vector_store import semantic_search

app = FastAPI(title="Planner Agent", version="1.1")
stm = ShortTermMemory()


def plan_steps(goal: str) -> list[str]:
    """Simple planning stub.

    Replace with Bedrock/OpenAI/LangGraph/etc.
    """

    return [
        f"Clarify the objective: {goal}",
        "Draft a short execution checklist",
        "Produce a final response payload",
    ]


@app.on_event("startup")
def startup():
    init_db()


@app.get("/health")
def health():
    return {"ok": True}


@app.post("/runs", response_model=StartRunResponse)
def start_run(req: StartRunRequest):
    run_id = str(uuid.uuid4())
    steps = plan_steps(req.goal)

    insert_run(run_id, req.goal)

    # Queue steps to worker via Redis + store durable plan in Aurora
    for i, step in enumerate(steps, start=1):
        insert_step(run_id, i, step, status="queued")
        stm.enqueue_task({"run_id": run_id, "step_num": i, "step_text": step})

    # STM scratchpad
    stm.set_scratch(run_id, "goal", req.goal)
    stm.set_scratch(run_id, "steps", steps)

    return StartRunResponse(run_id=run_id, steps=steps)


@app.get("/runs/{run_id}", response_model=RunStatusResponse)
def get_run(run_id: str):
    data = fetch_run(run_id)
    run = data["run"]
    if not run:
        return RunStatusResponse(run_id=run_id, goal="", steps=[])

    return RunStatusResponse(run_id=run_id, goal=run["goal"], steps=data["steps"])


@app.get("/search", response_model=SearchResponse)
def search(q: str, top_k: int = 5, run_id: str | None = None):
    hits = semantic_search(query_embedding=embed_text(q), top_k=top_k, run_id=run_id)
    return SearchResponse(query=q, top_k=top_k, run_id=run_id, hits=hits)
