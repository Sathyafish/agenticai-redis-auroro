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

# Database credentials - MUST be provided via terraform.tfvars or environment variables
# NEVER commit these values to version control
variable "db_username" {
  type        = string
  description = "Aurora PostgreSQL master username"
  sensitive   = true
}

variable "db_password" {
  type        = string
  description = "Aurora PostgreSQL master password (min 8 chars, must include uppercase, lowercase, and special chars)"
  sensitive   = true
  validation {
    condition     = length(var.db_password) >= 8
    error_message = "Database password must be at least 8 characters long."
  }
}

variable "db_name" {
  type        = string
  description = "Aurora PostgreSQL database name"
  default     = "agentic"
}
