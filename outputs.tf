output "cloudfront_domain_name" {
  description = "The domain name of the CloudFront distribution"
  value       = aws_cloudfront_distribution.main.domain_name
}

output "ecs_cluster_name" {
  description = "The name of the ECS cluster"
  value       = aws_ecs_cluster.main.name
}

output "ecs_service_name" {
  description = "The name of the ECS service"
  value       = aws_ecs_service.app.name
}

output "aurora_writer_endpoint" {
  description = "Aurora Cluster Writer Endpoint"
  value       = aws_rds_cluster.aurora.endpoint
}

output "aurora_reader_endpoint" {
  description = "Aurora Cluster Reader Endpoint"
  value       = aws_rds_cluster.aurora.reader_endpoint
}

output "aurora_database_name" {
  description = "Aurora Database Name"
  value       = aws_rds_cluster.aurora.database_name
}

output "aurora_master_username" {
  description = "Aurora Master Username"
  value       = aws_rds_cluster.aurora.master_username
}

output "aurora_master_password" {
  description = "Aurora Master Password"
  value       = random_password.db_password.result
  sensitive   = true
}
