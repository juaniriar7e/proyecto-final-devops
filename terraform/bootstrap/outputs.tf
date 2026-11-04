output "tf_state_bucket" {
  description = "Bucket de estado (variable de GitHub TF_STATE_BUCKET)."
  value       = aws_s3_bucket.state.bucket
}

output "aws_region" {
  description = "Región (variable de GitHub AWS_REGION)."
  value       = var.aws_region
}

output "role_infra_arn" {
  description = "ARN del rol del pipeline 1 (AWS_ROLE_INFRA)."
  value       = aws_iam_role.infra.arn
}

output "role_build_arn" {
  description = "ARN del rol del pipeline 2 (AWS_ROLE_BUILD)."
  value       = aws_iam_role.build.arn
}

output "role_deploy_arn" {
  description = "ARN del rol del pipeline 3 (AWS_ROLE_DEPLOY)."
  value       = aws_iam_role.deploy.arn
}

output "project_prefix" {
  description = "Prefijo de recursos (variable de GitHub PROJECT_PREFIX)."
  value       = local.prefix
}

output "github_oidc_provider_arn" {
  description = "ARN del proveedor OIDC de GitHub."
  value       = local.oidc_arn
}

output "github_variables" {
  description = "Variables de GitHub (no secretos) listas para cargar."
  value = {
    AWS_REGION      = var.aws_region
    AWS_ROLE_INFRA  = aws_iam_role.infra.arn
    AWS_ROLE_BUILD  = aws_iam_role.build.arn
    AWS_ROLE_DEPLOY = aws_iam_role.deploy.arn
    TF_STATE_BUCKET = aws_s3_bucket.state.bucket
    PROJECT_PREFIX  = local.prefix
  }
}
