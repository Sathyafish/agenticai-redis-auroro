import json
import os
from typing import Any, Dict, Optional

import redis

REDIS_HOST = os.getenv("REDIS_HOST", "localhost")
REDIS_PORT = int(os.getenv("REDIS_PORT", "6379"))
QUEUE_KEY = os.getenv("QUEUE_KEY", "agent:queue")


class ShortTermMemory:
    """Redis-backed short-term memory + work queue.

    - Queue: Redis list at QUEUE_KEY (LPUSH/BRPOP)
    - Per-run scratchpad: hash agent:run:<run_id>

    This is intentionally minimal to keep the sample easy to follow.
    """

    def __init__(self) -> None:
        self.r = redis.Redis(host=REDIS_HOST, port=REDIS_PORT, decode_responses=True)

    def enqueue_task(self, task: Dict[str, Any]) -> None:
        self.r.lpush(QUEUE_KEY, json.dumps(task))

    def dequeue_task_blocking(self, timeout_seconds: int = 5) -> Optional[Dict[str, Any]]:
        item = self.r.brpop(QUEUE_KEY, timeout=timeout_seconds)
        if not item:
            return None
        _, payload = item
        return json.loads(payload)

    def set_scratch(self, run_id: str, key: str, value: Any) -> None:
        self.r.hset(f"agent:run:{run_id}", key, json.dumps(value))

    def get_scratch(self, run_id: str, key: str) -> Optional[Any]:
        v = self.r.hget(f"agent:run:{run_id}", key)
        return json.loads(v) if v else None
