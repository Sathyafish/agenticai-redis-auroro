output "planner_url" {
  value = aws_lb.planner.dns_name
}

output "ecr_planner_repo" {
  value = aws_ecr_repository.planner.repository_url
}

output "ecr_worker_repo" {
  value = aws_ecr_repository.worker.repository_url
}

output "redis_endpoint" {
  value = aws_elasticache_replication_group.redis.primary_endpoint_address
}

output "aurora_endpoint" {
  value = aws_rds_cluster.aurora.endpoint
}
