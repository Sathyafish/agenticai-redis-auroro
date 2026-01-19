output "planner_url" {
  description = "Planner Agent ALB DNS name (HTTP endpoint)"
  value       = aws_lb.planner.dns_name
}

output "ecr_planner_repo" {
  description = "ECR repository URL for Planner Agent"
  value       = aws_ecr_repository.planner.repository_url
}

output "ecr_worker_repo" {
  description = "ECR repository URL for Worker Agent"
  value       = aws_ecr_repository.worker.repository_url
}

output "redis_endpoint" {
  description = "ElastiCache Redis primary endpoint address"
  value       = aws_elasticache_replication_group.redis.primary_endpoint_address
}

output "aurora_endpoint" {
  description = "Aurora PostgreSQL cluster writer endpoint"
  value       = aws_rds_cluster.aurora.endpoint
}

output "db_secret_arn" {
  description = "ARN of AWS Secrets Manager secret containing DB credentials"
  value       = aws_secretsmanager_secret.db.arn
}

output "db_secret_name" {
  description = "Name of AWS Secrets Manager secret containing DB credentials"
  value       = aws_secretsmanager_secret.db.name
}
