import os
import time

from services.common.db import init_db, update_step
from services.common.embeddings import embed_text
from services.common.memory import ShortTermMemory
from services.common.vector_store import insert_memory

stm = ShortTermMemory()
POLL_SECONDS = int(os.getenv("POLL_SECONDS", "2"))


def execute_step(step_text: str) -> str:
    """Execution stub.

    Replace with tool use + LLM calls later.
    """

    lower = step_text.lower()
    if lower.startswith("clarify"):
        return "Objective clarified into: scope, constraints, expected output."
    if "checklist" in lower:
        return "- Gather inputs\n- Generate draft\n- Validate\n- Persist output"
    if "final response" in lower:
        return "Final payload created and stored."
    return f"Executed: {step_text}"


def main():
    init_db()
    print("Worker started. Waiting for tasks...")

    while True:
        task = stm.dequeue_task_blocking(timeout_seconds=5)
        if not task:
            time.sleep(POLL_SECONDS)
            continue

        run_id = task["run_id"]
        step_num = int(task["step_num"])
        step_text = task["step_text"]

        try:
            update_step(run_id, step_num, status="running", result=None)
            result = execute_step(step_text)
            update_step(run_id, step_num, status="done", result=result)

            # STM scratchpad for quick recent context
            stm.set_scratch(run_id, f"step:{step_num}:result", result)

            # LTM semantic memory (pgvector)
            insert_memory(
                run_id=run_id,
                source="worker",
                content=result,
                embedding=embed_text(result),
                metadata={"step_num": step_num, "kind": "step_result"},
            )

            print(f"[{run_id}] step {step_num} done")
        except Exception as e:
            update_step(run_id, step_num, status="error", result=str(e))
            print(f"[{run_id}] step {step_num} error: {e}")


if __name__ == "__main__":
    main()
