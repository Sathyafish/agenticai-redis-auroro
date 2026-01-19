variable "aws_region" {
  type    = string
  default = "us-west-2"
}

variable "project_name" {
  type    = string
  default = "agentic-sample"
}

variable "vpc_cidr" { type = string, default = "10.10.0.0/16" }

variable "public_subnet_a_cidr" { type = string, default = "10.10.1.0/24" }
variable "public_subnet_b_cidr" { type = string, default = "10.10.2.0/24" }
variable "private_subnet_a_cidr" { type = string, default = "10.10.11.0/24" }
variable "private_subnet_b_cidr" { type = string, default = "10.10.12.0/24" }

variable "redis_node_type" {
  type    = string
  default = "cache.t4g.micro"
}

# Use a modern Aurora PostgreSQL version so pgvector features (incl. HNSW) are more likely available.
variable "aurora_engine_version" {
  type    = string
  default = "16.6"
}

variable "aurora_min_acu" { type = number, default = 0.5 }
variable "aurora_max_acu" { type = number, default = 2 }

# Demo credentials (do NOT commit real secrets)
variable "db_username" { type = string, default = "appuser" }
variable "db_password" { type = string, default = "ChangeMe123!ChangeMe123!" }
variable "db_name"     { type = string, default = "agentic" }
