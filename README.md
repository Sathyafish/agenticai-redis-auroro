# Agentic AI System with Redis STM & Aurora pgvector LTM

A production-ready **multi-agent AI system** deployed on **AWS ECS Fargate** with hybrid memory architecture:
- **Short-Term Memory (STM)**: ElastiCache Redis for fast task queuing and scratchpad operations
- **Long-Term Memory (LTM)**: Aurora PostgreSQL Serverless v2 with pgvector for semantic retrieval

## 🎯 Overview

This project demonstrates a scalable agentic AI architecture with two specialized agents:

### **Planner Agent** (FastAPI Service)
- Accepts high-level goals from users
- Generates execution plans (decomposed into steps)
- Stores durable run/step records in Aurora PostgreSQL
- Enqueues step tasks to Redis for asynchronous processing
- Provides semantic search over historical executions
- Exposed via Application Load Balancer (ALB)

### **Worker Agent** (Background Service)
- Consumes tasks from Redis queue
- Executes individual steps with autonomy
- Updates step status and results in Aurora
- Stores execution results as semantic memories in pgvector
- Enables intelligent retrieval of past knowledge

## 🏗️ Architecture

```
┌─────────────┐         ┌──────────────────┐         ┌─────────────┐
│   Client    │────────▶│  Planner Agent   │────────▶│   Redis     │
│   (HTTP)    │         │  (FastAPI/ALB)   │         │   (STM)     │
└─────────────┘         └──────────────────┘         └─────────────┘
                                │                             │
                                │                             │
                                ▼                             ▼
                        ┌──────────────────┐         ┌─────────────┐
                        │ Aurora PostgreSQL│◀────────│   Worker    │
                        │ + pgvector (LTM) │         │   Agent     │
                        └──────────────────┘         └─────────────┘
```

### Memory Architecture

| Layer | Technology | Purpose | Data Types |
|-------|-----------|---------|-----------|
| **STM** | ElastiCache Redis | Task queue, scratchpad, temporary state | Task metadata, recent context |
| **LTM** | Aurora PostgreSQL + pgvector | Durable storage, semantic retrieval | Run history, step results, embeddings |

### Database Schema

**Aurora PostgreSQL Tables:**
- `agent_runs`: Execution metadata (run_id, goal, created_at)
- `agent_steps`: Step tracking (run_id, step_num, status, result)
- `semantic_memories`: Vector embeddings (pgvector) for semantic search

## 🚀 Tech Stack

- **Container Orchestration**: AWS ECS Fargate
- **API Framework**: FastAPI (Python 3.11+)
- **Message Queue**: ElastiCache Redis (cache.t4g.micro)
- **Vector Database**: Aurora PostgreSQL Serverless v2 (16.6) with pgvector
- **Infrastructure as Code**: Terraform
- **Containerization**: Docker

## 📦 Project Structure

```
agenticai-redis-auroro/
├── agentic-code/
│   ├── services/
│   │   ├── common/           # Shared modules
│   │   │   ├── db.py         # Aurora database operations
│   │   │   ├── embeddings.py # Text embedding (demo impl)
│   │   │   ├── memory.py     # Redis STM interface
│   │   │   ├── models.py     # Pydantic data models
│   │   │   └── vector_store.py # pgvector operations
│   │   ├── planner/          # Planner Agent
│   │   │   ├── Dockerfile
│   │   │   ├── main.py       # FastAPI endpoints
│   │   │   └── requirements.txt
│   │   └── worker/           # Worker Agent
│   │       ├── Dockerfile
│   │       ├── main.py       # Task processor
│   │       └── requirements.txt
│   ├── terraform/            # Infrastructure
│   │   ├── main.tf           # VPC, ECS, Redis, Aurora
│   │   ├── outputs.tf        # URLs, endpoints
│   │   └── variables.tf      # Configuration
│   └── README.md
└── README.md
```

## 🛠️ Setup & Deployment

### Prerequisites

- AWS CLI configured with appropriate credentials
- Terraform >= 1.0
- Docker
- jq (for JSON parsing in examples)

### Step 1: Provision Infrastructure

```bash
cd agentic-code/terraform
terraform init
terraform apply
```

This creates:
- VPC with public/private subnets across 2 AZs
- ElastiCache Redis cluster
- Aurora PostgreSQL Serverless v2 cluster with pgvector
- ECS Fargate cluster with task definitions
- Application Load Balancer
- ECR repositories
- Security groups and IAM roles

### Step 2: Build & Push Docker Images

Get ECR repository URLs from Terraform outputs:

```bash
terraform output ecr_planner_repo
terraform output ecr_worker_repo
```

Authenticate Docker to ECR:

```bash
aws ecr get-login-password --region us-west-2 | \
  docker login --username AWS --password-stdin <ACCOUNT_ID>.dkr.ecr.us-west-2.amazonaws.com
```

Build and push images:

```bash
# From repository root
cd /Users/narayas/Documents/DES\ Project\ Sathya/agenticai-redis-auroro

# Set repository URLs
PLANNER_REPO=$(cd agentic-code/terraform && terraform output -raw ecr_planner_repo)
WORKER_REPO=$(cd agentic-code/terraform && terraform output -raw ecr_worker_repo)

# Build and push Planner Agent
docker build -t ${PLANNER_REPO}:latest -f agentic-code/services/planner/Dockerfile ./agentic-code
docker push ${PLANNER_REPO}:latest

# Build and push Worker Agent
docker build -t ${WORKER_REPO}:latest -f agentic-code/services/worker/Dockerfile ./agentic-code
docker push ${WORKER_REPO}:latest
```

### Step 3: Deploy Services

Update ECS services to use the new images (automatic if using `:latest` tag):

```bash
aws ecs update-service --cluster agentic-sample-cluster \
  --service planner-service --force-new-deployment --region us-west-2

aws ecs update-service --cluster agentic-sample-cluster \
  --service worker-service --force-new-deployment --region us-west-2
```

## 📡 API Usage

### Get the Planner URL

```bash
cd agentic-code/terraform
terraform output planner_url
```

### Start a New Run

```bash
curl -X POST "http://<planner_url>/runs" \
  -H 'Content-Type: application/json' \
  -d '{
    "goal": "Create a comprehensive 3-bullet release note for Q1 features"
  }' | jq
```

**Response:**
```json
{
  "run_id": "a1b2c3d4-e5f6-7890-abcd-ef1234567890",
  "steps": [
    "Clarify the objective: Create a comprehensive 3-bullet release note for Q1 features",
    "Draft a short execution checklist",
    "Produce a final response payload"
  ]
}
```

### Check Run Status

```bash
curl "http://<planner_url>/runs/<run_id>" | jq
```

**Response:**
```json
{
  "run_id": "a1b2c3d4-e5f6-7890-abcd-ef1234567890",
  "goal": "Create a comprehensive 3-bullet release note for Q1 features",
  "steps": [
    {
      "step_num": 1,
      "step_text": "Clarify the objective: ...",
      "status": "done",
      "result": "Objective clarified into: scope, constraints, expected output.",
      "created_at": "2026-01-18T10:30:00Z",
      "updated_at": "2026-01-18T10:30:05Z"
    },
    ...
  ]
}
```

### Semantic Search (pgvector)

Search across all runs:

```bash
curl "http://<planner_url>/search?q=checklist&top_k=5" | jq
```

Search within a specific run:

```bash
curl "http://<planner_url>/search?q=objective&run_id=<run_id>&top_k=5" | jq
```

**Response:**
```json
{
  "query": "checklist",
  "top_k": 5,
  "run_id": null,
  "hits": [
    {
      "id": 123,
      "run_id": "...",
      "source": "worker",
      "content": "- Gather inputs\n- Generate draft\n- Validate\n- Persist output",
      "metadata": {"step_num": 2, "kind": "step_result"},
      "distance": 0.234,
      "created_at": "2026-01-18T10:30:10Z"
    },
    ...
  ]
}
```

### Health Check

```bash
curl "http://<planner_url>/health" | jq
```

## 🔧 Configuration

### Environment Variables

**Planner Agent:**
- `REDIS_HOST`: ElastiCache endpoint (auto-injected by ECS)
- `REDIS_PORT`: Redis port (default: 6379)
- `DB_HOST`: Aurora writer endpoint (auto-injected)
- `DB_PORT`: PostgreSQL port (default: 5432)
- `DB_NAME`: Database name (default: agentic)
- `DB_USER`: Database username
- `DB_PASSWORD`: Database password

**Worker Agent:**
- Same as Planner, plus:
- `POLL_SECONDS`: Task polling interval (default: 2)

### Terraform Variables

Edit `agentic-code/terraform/variables.tf`:

```hcl
variable "aws_region" { default = "us-west-2" }
variable "redis_node_type" { default = "cache.t4g.micro" }
variable "aurora_engine_version" { default = "16.6" }
variable "aurora_min_acu" { default = 0.5 }
variable "aurora_max_acu" { default = 2 }
```

## 🔒 Security Considerations

### Current Implementation (Demo)
⚠️ **WARNING**: The current setup uses demo credentials hardcoded in `variables.tf`:
- `db_username`: appuser
- `db_password`: ChangeMe123!ChangeMe123!

### Production Recommendations

1. **Use AWS Secrets Manager**:
   ```bash
   aws secretsmanager create-secret --name agentic/db/password \
     --secret-string '{"password":"<strong-password>"}'
   ```

2. **Enable VPC Endpoints**: Add VPC endpoints for ECR, Secrets Manager, CloudWatch
3. **Enable Aurora Encryption**: Use KMS for data-at-rest encryption
4. **Implement IAM Roles**: Use task-level IAM roles instead of credentials
5. **Enable WAF**: Add AWS WAF rules to ALB
6. **Rotate Credentials**: Implement automatic secret rotation
7. **Network Isolation**: Ensure services run in private subnets with NAT gateway

## 📊 Monitoring & Logging

### CloudWatch Logs
- Log Group: `/ecs/agentic-sample-planner`
- Log Group: `/ecs/agentic-sample-worker`

### Metrics to Monitor
- **ECS**: CPU/Memory utilization, task count
- **Redis**: Cache hit rate, evictions, connections
- **Aurora**: Query latency, connections, storage
- **ALB**: Request count, latency, error rates

### View Logs

```bash
aws logs tail /ecs/agentic-sample-planner --follow --region us-west-2
aws logs tail /ecs/agentic-sample-worker --follow --region us-west-2
```

## 🚧 Current Limitations & Future Enhancements

### Current Limitations

1. **Demo Embeddings**: Uses deterministic hash-based embeddings
   - Replace `services/common/embeddings.py` with real embedding service:
     - AWS Bedrock Titan Embeddings
     - OpenAI Embeddings API
     - Cohere Embeddings
     - Sentence Transformers (self-hosted)

2. **Simple Planning**: Hardcoded 3-step plans
   - Integrate LLM-based planning (GPT-4, Claude, Bedrock)
   - Implement LangGraph for complex workflows
   - Add dynamic plan adjustment based on execution feedback

3. **Basic Step Execution**: Stub implementation
   - Add tool use capabilities (web search, API calls, data processing)
   - Implement reasoning loops (ReAct, Chain-of-Thought)
   - Add human-in-the-loop approval gates

### Planned Enhancements

- [ ] Replace demo embeddings with Bedrock Titan
- [ ] Integrate LLM for intelligent planning (Claude 3 Sonnet)
- [ ] Add vector index optimization (HNSW vs IVFFlat)
- [ ] Implement step retry logic with exponential backoff
- [ ] Add WebSocket support for real-time updates
- [ ] Create admin dashboard (React + Vite)
- [ ] Add authentication/authorization (Cognito)
- [ ] Implement cost tracking and budget alerts
- [ ] Add distributed tracing (X-Ray)
- [ ] Support multi-tenancy

## 🧪 Testing

### Local Development

```bash
# Start local Redis
docker run -d -p 6379:6379 redis:7-alpine

# Start local PostgreSQL with pgvector
docker run -d -p 5432:5432 \
  -e POSTGRES_PASSWORD=postgres \
  -e POSTGRES_DB=agentic \
  pgvector/pgvector:pg16

# Install dependencies
cd agentic-code/services/planner
pip install -r requirements.txt

# Set environment variables
export REDIS_HOST=localhost
export DB_HOST=localhost
export DB_USER=postgres
export DB_PASSWORD=postgres
export DB_NAME=agentic

# Run Planner
uvicorn main:app --reload

# In another terminal, run Worker
cd ../worker
pip install -r requirements.txt
python main.py
```

### Run Tests

```bash
# TODO: Add pytest test suite
pytest tests/ -v --cov=services
```

## 📝 Notes

- **pgvector Index Type**: If your Aurora version doesn't support HNSW indexing, modify `services/common/db.py` to use `ivfflat`:
  ```sql
  CREATE INDEX IF NOT EXISTS semantic_memories_embedding_idx 
  ON semantic_memories USING ivfflat(embedding vector_cosine_ops);
  ```

- **Cost Optimization**: Aurora Serverless v2 scales down to 0.5 ACU when idle. Consider pausing non-production clusters.

- **Scaling**: Adjust ECS task count in `terraform/main.tf` based on workload:
  ```hcl
  desired_count = 2  # Increase for higher throughput
  ```

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Commit changes (`git commit -m 'Add amazing feature'`)
4. Push to branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## 📄 License

This project is provided as-is for demonstration purposes.

## 📧 Support

For issues or questions, please open a GitHub issue or contact the maintainer.

---

**Built with ❤️ using AWS, FastAPI, Redis, and PostgreSQL pgvector**
