terraform {
  required_version = ">= 1.6.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

data "aws_caller_identity" "current" {}

locals {
  name = var.project_name
  tags = {
    Project = var.project_name
  }
}

# -----------------------------
# Networking: VPC, subnets, NAT
# -----------------------------
resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true
  tags                 = merge(local.tags, { Name = "${local.name}-vpc" })
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.this.id
  tags   = merge(local.tags, { Name = "${local.name}-igw" })
}

resource "aws_subnet" "public_a" {
  vpc_id                  = aws_vpc.this.id
  cidr_block              = var.public_subnet_a_cidr
  availability_zone       = "${var.aws_region}a"
  map_public_ip_on_launch = true
  tags                    = merge(local.tags, { Name = "${local.name}-public-a" })
}

resource "aws_subnet" "public_b" {
  vpc_id                  = aws_vpc.this.id
  cidr_block              = var.public_subnet_b_cidr
  availability_zone       = "${var.aws_region}b"
  map_public_ip_on_launch = true
  tags                    = merge(local.tags, { Name = "${local.name}-public-b" })
}

resource "aws_subnet" "private_a" {
  vpc_id            = aws_vpc.this.id
  cidr_block        = var.private_subnet_a_cidr
  availability_zone = "${var.aws_region}a"
  tags              = merge(local.tags, { Name = "${local.name}-private-a" })
}

resource "aws_subnet" "private_b" {
  vpc_id            = aws_vpc.this.id
  cidr_block        = var.private_subnet_b_cidr
  availability_zone = "${var.aws_region}b"
  tags              = merge(local.tags, { Name = "${local.name}-private-b" })
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id
  tags   = merge(local.tags, { Name = "${local.name}-rt-public" })
}

resource "aws_route" "public_default" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.igw.id
}

resource "aws_route_table_association" "public_a" {
  subnet_id      = aws_subnet.public_a.id
  route_table_id = aws_route_table.public.id
}
resource "aws_route_table_association" "public_b" {
  subnet_id      = aws_subnet.public_b.id
  route_table_id = aws_route_table.public.id
}

resource "aws_eip" "nat" {
  domain = "vpc"
  tags   = merge(local.tags, { Name = "${local.name}-nat-eip" })
}

resource "aws_nat_gateway" "nat" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public_a.id
  tags          = merge(local.tags, { Name = "${local.name}-nat" })
  depends_on    = [aws_internet_gateway.igw]
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.this.id
  tags   = merge(local.tags, { Name = "${local.name}-rt-private" })
}

resource "aws_route" "private_default" {
  route_table_id         = aws_route_table.private.id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.nat.id
}

resource "aws_route_table_association" "private_a" {
  subnet_id      = aws_subnet.private_a.id
  route_table_id = aws_route_table.private.id
}
resource "aws_route_table_association" "private_b" {
  subnet_id      = aws_subnet.private_b.id
  route_table_id = aws_route_table.private.id
}

# -----------------------------
# Security Groups
# -----------------------------
resource "aws_security_group" "alb_sg" {
  name        = "${local.name}-alb-sg"
  description = "ALB SG"
  vpc_id      = aws_vpc.this.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = local.tags
}

resource "aws_security_group" "ecs_sg" {
  name        = "${local.name}-ecs-sg"
  description = "ECS tasks SG"
  vpc_id      = aws_vpc.this.id

  # Planner service port (FastAPI)
  ingress {
    from_port       = 8080
    to_port         = 8080
    protocol        = "tcp"
    security_groups = [aws_security_group.alb_sg.id]
  }

  # Internal-only task-to-task comms
  ingress {
    from_port = 0
    to_port   = 65535
    protocol  = "tcp"
    self      = true
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = local.tags
}

resource "aws_security_group" "redis_sg" {
  name        = "${local.name}-redis-sg"
  description = "Redis SG"
  vpc_id      = aws_vpc.this.id

  ingress {
    from_port       = 6379
    to_port         = 6379
    protocol        = "tcp"
    security_groups = [aws_security_group.ecs_sg.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = local.tags
}

resource "aws_security_group" "db_sg" {
  name        = "${local.name}-db-sg"
  description = "Aurora SG"
  vpc_id      = aws_vpc.this.id

  ingress {
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.ecs_sg.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = local.tags
}

# -----------------------------
# Redis (ElastiCache)
# -----------------------------
resource "aws_elasticache_subnet_group" "redis" {
  name       = "${local.name}-redis-subnets"
  subnet_ids = [aws_subnet.private_a.id, aws_subnet.private_b.id]
  tags       = local.tags
}

resource "aws_elasticache_replication_group" "redis" {
  replication_group_id       = "${local.name}-redis"
  description                = "STM Redis"
  engine                     = "redis"
  engine_version             = "7.1"
  node_type                  = var.redis_node_type
  num_cache_clusters         = 1
  port                       = 6379
  subnet_group_name          = aws_elasticache_subnet_group.redis.name
  security_group_ids         = [aws_security_group.redis_sg.id]
  automatic_failover_enabled = false
  tags                       = local.tags
}

# -----------------------------
# Aurora PostgreSQL (Serverless v2)
# -----------------------------
resource "aws_db_subnet_group" "aurora" {
  name       = "${local.name}-aurora-subnets"
  subnet_ids = [aws_subnet.private_a.id, aws_subnet.private_b.id]
  tags       = local.tags
}

resource "aws_secretsmanager_secret" "db" {
  name = "${local.name}-db-credentials"
  tags = local.tags
}

resource "aws_secretsmanager_secret_version" "db" {
  secret_id = aws_secretsmanager_secret.db.id
  secret_string = jsonencode({
    username = var.db_username
    password = var.db_password
    dbname   = var.db_name
  })
}

resource "aws_rds_cluster" "aurora" {
  cluster_identifier      = "${local.name}-aurora"
  engine                 = "aurora-postgresql"
  engine_version         = var.aurora_engine_version
  database_name          = var.db_name
  master_username        = var.db_username
  master_password        = var.db_password
  db_subnet_group_name   = aws_db_subnet_group.aurora.name
  vpc_security_group_ids = [aws_security_group.db_sg.id]

  serverlessv2_scaling_configuration {
    min_capacity = var.aurora_min_acu
    max_capacity = var.aurora_max_acu
  }

  skip_final_snapshot = true
  tags                = local.tags
}

resource "aws_rds_cluster_instance" "aurora_writer" {
  identifier         = "${local.name}-aurora-writer-1"
  cluster_identifier = aws_rds_cluster.aurora.id
  instance_class     = "db.serverless"
  engine             = aws_rds_cluster.aurora.engine
  engine_version     = aws_rds_cluster.aurora.engine_version
  tags               = local.tags
}

# -----------------------------
# ECS Cluster
# -----------------------------
resource "aws_ecs_cluster" "this" {
  name = "${local.name}-cluster"
  tags = local.tags
}

# -----------------------------
# ECR Repos (build/push images)
# -----------------------------
resource "aws_ecr_repository" "planner" {
  name = "${local.name}-planner"
  tags = local.tags
}

resource "aws_ecr_repository" "worker" {
  name = "${local.name}-worker"
  tags = local.tags
}

# -----------------------------
# IAM Roles for ECS
# -----------------------------
data "aws_iam_policy_document" "ecs_task_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "task_execution" {
  name               = "${local.name}-ecs-exec-role"
  assume_role_policy = data.aws_iam_policy_document.ecs_task_assume.json
  tags               = local.tags
}

resource "aws_iam_role_policy_attachment" "task_execution_policy" {
  role       = aws_iam_role.task_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

# IAM policy to read DB credentials from Secrets Manager
data "aws_iam_policy_document" "secrets_read" {
  statement {
    actions   = ["secretsmanager:GetSecretValue"]
    resources = [aws_secretsmanager_secret.db.arn]
  }
}

resource "aws_iam_policy" "secrets_read" {
  name   = "${local.name}-secrets-read"
  policy = data.aws_iam_policy_document.secrets_read.json
  tags   = local.tags
}

# Attach secrets policy to EXECUTION role (required for ECS to pull secrets at task startup)
resource "aws_iam_role_policy_attachment" "task_execution_secrets_read" {
  role       = aws_iam_role.task_execution.name
  policy_arn = aws_iam_policy.secrets_read.arn
}

resource "aws_iam_role" "task_role" {
  name               = "${local.name}-ecs-task-role"
  assume_role_policy = data.aws_iam_policy_document.ecs_task_assume.json
  tags               = local.tags
}

# Minimal Bedrock invoke permissions
resource "aws_iam_policy" "bedrock_invoke" {
  name = "${local.name}-bedrock-invoke"
  path = "/"
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Sid    = "InvokeBedrockModels",
        Effect = "Allow",
        Action = [
          "bedrock:InvokeModel",
          "bedrock:InvokeModelWithResponseStream",
          "bedrock:ListFoundationalModels",
          "bedrock:GetModel"
        ],
        Resource = "*"
      }
    ]
  })
  tags = local.tags
}

resource "aws_iam_role_policy_attachment" "task_bedrock_invoke_attach" {
  role       = aws_iam_role.task_role.name
  policy_arn = aws_iam_policy.bedrock_invoke.arn
}

# -----------------------------
# CloudWatch Logs
# -----------------------------
resource "aws_cloudwatch_log_group" "planner" {
  name              = "/ecs/${local.name}/planner"
  retention_in_days = 14
  tags              = local.tags
}

resource "aws_cloudwatch_log_group" "worker" {
  name              = "/ecs/${local.name}/worker"
  retention_in_days = 14
  tags              = local.tags
}

# -----------------------------
# ALB for Planner API
# -----------------------------
resource "aws_lb" "planner" {
  name               = "${local.name}-planner-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb_sg.id]
  subnets            = [aws_subnet.public_a.id, aws_subnet.public_b.id]
  tags               = local.tags
}

resource "aws_lb_target_group" "planner" {
  name        = "${local.name}-planner-tg"
  port        = 8080
  protocol    = "HTTP"
  vpc_id      = aws_vpc.this.id
  target_type = "ip"

  health_check {
    path = "/health"
  }

  tags = local.tags
}

resource "aws_lb_listener" "planner_http" {
  load_balancer_arn = aws_lb.planner.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.planner.arn
  }
}

# -----------------------------
# ECS Task Definitions + Services
# -----------------------------
resource "aws_ecs_task_definition" "planner" {
  family                   = "${local.name}-planner"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = "256"
  memory                   = "512"
  execution_role_arn       = aws_iam_role.task_execution.arn
  task_role_arn            = aws_iam_role.task_role.arn

  container_definitions = jsonencode([
    {
      name      = "planner"
      image     = "${aws_ecr_repository.planner.repository_url}:latest"
      essential = true
      portMappings = [
        { containerPort = 8080, hostPort = 8080, protocol = "tcp" }
      ]
      environment = [
        { name = "REDIS_HOST", value = aws_elasticache_replication_group.redis.primary_endpoint_address },
        { name = "REDIS_PORT", value = "6379" },
        { name = "AURORA_HOST", value = aws_rds_cluster.aurora.endpoint },
        { name = "AURORA_PORT", value = "5432" },
        { name = "QUEUE_KEY", value = "agent:queue" },
        { name = "USE_BEDROCK", value = "true" },
        { name = "BEDROCK_REGION", value = var.aws_region },
        { name = "EMBEDDING_MODEL_ID", value = "amazon.titan-embed-text-v2:0" },
        { name = "PLANNER_MODEL_ID", value = var.planner_model_id },
        { name = "EMBED_DIM", value = "1024" }
      ]
      secrets = [
        { name = "AURORA_DB", valueFrom = "${aws_secretsmanager_secret.db.arn}:dbname::" },
        { name = "AURORA_USER", valueFrom = "${aws_secretsmanager_secret.db.arn}:username::" },
        { name = "AURORA_PASSWORD", valueFrom = "${aws_secretsmanager_secret.db.arn}:password::" }
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.planner.name
          awslogs-region        = var.aws_region
          awslogs-stream-prefix = "ecs"
        }
      }
    }
  ])

  tags = local.tags
}

resource "aws_ecs_task_definition" "worker" {
  family                   = "${local.name}-worker"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = "256"
  memory                   = "512"
  execution_role_arn       = aws_iam_role.task_execution.arn
  task_role_arn            = aws_iam_role.task_role.arn

  container_definitions = jsonencode([
    {
      name      = "worker"
      image     = "${aws_ecr_repository.worker.repository_url}:latest"
      essential = true
      environment = [
        { name = "REDIS_HOST", value = aws_elasticache_replication_group.redis.primary_endpoint_address },
        { name = "REDIS_PORT", value = "6379" },
        { name = "AURORA_HOST", value = aws_rds_cluster.aurora.endpoint },
        { name = "AURORA_PORT", value = "5432" },
        { name = "QUEUE_KEY", value = "agent:queue" },
        { name = "POLL_SECONDS", value = "2" },
        { name = "USE_BEDROCK", value = "true" },
        { name = "BEDROCK_REGION", value = var.aws_region },
        { name = "EMBEDDING_MODEL_ID", value = "amazon.titan-embed-text-v2:0" },
        { name = "PLANNER_MODEL_ID", value = var.planner_model_id },
        { name = "EMBED_DIM", value = "1024" }
      ]
      secrets = [
        { name = "AURORA_DB", valueFrom = "${aws_secretsmanager_secret.db.arn}:dbname::" },
        { name = "AURORA_USER", valueFrom = "${aws_secretsmanager_secret.db.arn}:username::" },
        { name = "AURORA_PASSWORD", valueFrom = "${aws_secretsmanager_secret.db.arn}:password::" }
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.worker.name
          awslogs-region        = var.aws_region
          awslogs-stream-prefix = "ecs"
        }
      }
    }
  ])

  tags = local.tags
}

resource "aws_ecs_service" "planner" {
  name            = "${local.name}-planner-svc"
  cluster         = aws_ecs_cluster.this.id
  task_definition = aws_ecs_task_definition.planner.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = [aws_subnet.private_a.id, aws_subnet.private_b.id]
    security_groups  = [aws_security_group.ecs_sg.id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.planner.arn
    container_name   = "planner"
    container_port   = 8080
  }

  tags = local.tags
}

resource "aws_ecs_service" "worker" {
  name            = "${local.name}-worker-svc"
  cluster         = aws_ecs_cluster.this.id
  task_definition = aws_ecs_task_definition.worker.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = [aws_subnet.private_a.id, aws_subnet.private_b.id]
    security_groups  = [aws_security_group.ecs_sg.id]
    assign_public_ip = false
  }

  tags = local.tags
}
