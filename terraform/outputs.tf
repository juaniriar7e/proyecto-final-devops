output "alb_url" {
  description = "URL pública de la aplicación (HTTP)."
  value       = "http://${module.alb.dns_name}"
}

output "ecr_repository_urls" {
  description = "URL de cada repositorio ECR."
  value       = module.ecr.repository_urls
}

output "ecr_repository_names" {
  description = "Nombre de cada repositorio ECR."
  value       = module.ecr.repository_names
}

output "ecs_cluster_name" {
  description = "Nombre del clúster ECS."
  value       = module.ecs.cluster_name
}

output "ecs_service_names" {
  description = "Nombre de cada servicio ECS."
  value       = module.ecs.service_names
}

output "dynamodb_table_name" {
  description = "Tabla DynamoDB de tareas."
  value       = module.data.table_name
}

output "aws_account_id" {
  description = "Cuenta de AWS en uso (obtenida en tiempo de ejecución)."
  value       = data.aws_caller_identity.current.account_id
}
