output "cluster_name" {
  value = aws_ecs_cluster.this.name
}

output "service_names" {
  value = { for k, s in aws_ecs_service.this : k => s.name }
}

output "execution_role_arn" {
  value = aws_iam_role.execution.arn
}
