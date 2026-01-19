from pydantic import BaseModel
from typing import List, Optional, Any


class StartRunRequest(BaseModel):
    goal: str


class StartRunResponse(BaseModel):
    run_id: str
    steps: List[str]


class RunStatusResponse(BaseModel):
    run_id: str
    goal: str
    steps: list


class SearchResponse(BaseModel):
    query: str
    top_k: int
    run_id: Optional[str] = None
    hits: list
