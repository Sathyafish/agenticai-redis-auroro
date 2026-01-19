# agentic-sample (ECS Fargate + Redis STM + Aurora pgvector LTM)

A minimal **2-agent** sample deployed on **AWS ECS Fargate**:

- **Planner Agent** (FastAPI behind ALB):
  - accepts a goal
  - generates a simple plan (3 steps)
  - stores durable run/steps in Aurora
  - enqueues step tasks to Redis
- **Worker Agent**:
  - consumes tasks from Redis
  - executes each step
  - updates step status/results in Aurora
  - writes each result into **Aurora pgvector** (`semantic_memories`) for semantic retrieval

## Architecture

- STM: **ElastiCache Redis** queue + scratchpad
- LTM: **Aurora PostgreSQL Serverless v2**
  - relational history: `agent_runs`, `agent_steps`
  - semantic memory: `semantic_memories` with `pgvector`

## Deploy

### 1) Provision infra

```bash
cd terraform
terraform init
terraform apply
```

### 2) Build + push Docker images

Terraform outputs ECR repo URLs:

```bash
terraform output ecr_planner_repo
terraform output ecr_worker_repo
```

Authenticate docker to ECR:

```bash
aws ecr get-login-password --region us-west-2 | docker login --username AWS --password-stdin <ACCOUNT_ID>.dkr.ecr.us-west-2.amazonaws.com
```

Build and push:

```bash
# from repo root
PLANNER_REPO=<terraform output ecr_planner_repo>
WORKER_REPO=<terraform output ecr_worker_repo>

# planner
docker build -t ${PLANNER_REPO}:latest -f services/planner/Dockerfile .
docker push ${PLANNER_REPO}:latest

# worker
docker build -t ${WORKER_REPO}:latest -f services/worker/Dockerfile .
docker push ${WORKER_REPO}:latest
```

### 3) Use the API

Get the ALB URL:

```bash
terraform output planner_url
```

Start a run:

```bash
curl -s -X POST "http://<planner_url>/runs" \
  -H 'content-type: application/json' \
  -d '{"goal":"Create a 3-bullet release note"}' | jq
```

Poll run status:

```bash
curl -s "http://<planner_url>/runs/<run_id>" | jq
```

Semantic search over long-term memories (pgvector):

```bash
curl -s "http://<planner_url>/search?q=checklist&top_k=5" | jq
# or scoped
curl -s "http://<planner_url>/search?q=objective&run_id=<run_id>&top_k=5" | jq
```

## Notes

- This uses a deterministic **demo embedding** to keep the sample lightweight. Replace `services/common/embeddings.py` with a real embedding provider (Bedrock Titan, OpenAI, etc.).
- If your pgvector build doesn’t support **HNSW**, change the index in `services/common/db.py` to `ivfflat`.
