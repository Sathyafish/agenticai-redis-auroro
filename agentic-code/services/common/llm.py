# services/common/llm.py
from __future__ import annotations

import json
import os

import boto3

BEDROCK_REGION = os.getenv("BEDROCK_REGION", "us-west-2")
PLANNER_MODEL_ID = os.getenv("PLANNER_MODEL_ID", "")
USE_BEDROCK = os.getenv("USE_BEDROCK", "true").lower() in ("1", "true", "yes")


def call_planner_model(prompt: str, max_tokens: int = 512, temperature: float = 0.0) -> str:
    """Calls a conversation-style Claude-like model on Bedrock using the messages API format.

    The exact request body varies by model; for Anthropic Claude we use the 'messages' style.
    """
    if not USE_BEDROCK or not PLANNER_MODEL_ID:
        # simple local fallback: deterministic split into 3 steps
        return "\n".join([
            f"Clarify the objective: {prompt}",
            "Draft a short execution checklist",
            "Produce a final response payload",
        ])

    client = boto3.client("bedrock-runtime", region_name=BEDROCK_REGION)

    # Native request for Anthropic Claude Messages API on Bedrock
    native_request = {
        "messages": [
            {
                "role": "system",
                "content": [{"type": "text", "text": "You are a planning agent. Break the user goal into 3 short executable steps."}],
            },
            {"role": "user", "content": [{"type": "text", "text": prompt}]},
        ],
        "max_tokens": max_tokens,
        "temperature": temperature,
    }

    resp = client.invoke_model(
        modelId=PLANNER_MODEL_ID,
        body=json.dumps(native_request),
        contentType="application/json",
        accept="application/json",
    )

    payload_bytes = resp["body"].read()
    payload = json.loads(payload_bytes.decode("utf-8"))

    # For Anthropic/Claude we commonly find the assistant text in payload["content"] or payload["outputs"].
    # Try a few patterns:
    if isinstance(payload, dict):
        # Typical layout: payload["outputs"][0]["content"][0]["text"] or payload["content"] etc.
        if "outputs" in payload and payload["outputs"]:
            first_out = payload["outputs"][0]
            # sometimes nested structures; flatten best-effort
            if isinstance(first_out, dict):
                # look for content -> list -> text
                if "content" in first_out and isinstance(first_out["content"], list):
                    for chunk in first_out["content"]:
                        if isinstance(chunk, dict) and "text" in chunk:
                            return chunk["text"]
                # fallback to 'text' directly
                if "text" in first_out:
                    return first_out["text"]
        # some models return 'content' top-level
        if "content" in payload:
            if isinstance(payload["content"], list):
                for chunk in payload["content"]:
                    if isinstance(chunk, dict) and "text" in chunk:
                        return chunk["text"]
            elif isinstance(payload["content"], str):
                return payload["content"]

    # Last resort: return full JSON
    return json.dumps(payload)
