variable "name" {
  description = "Prefijo de nombres."
  type        = string
}

variable "aws_region" {
  type = string
}

variable "subnet_ids" {
  type = list(string)
}

variable "security_group_id" {
  type = string
}

variable "repository_urls" {
  description = "URL de ECR por servicio (frontend, backend)."
  type        = map(string)
}

variable "target_group_arns" {
  description = "ARN del target group por servicio (frontend, backend)."
  type        = map(string)
}

variable "dynamodb_table_name" {
  type = string
}

variable "dynamodb_table_arn" {
  type = string
}

variable "log_retention_days" {
  type    = number
  default = 7
}

variable "task_cpu" {
  type    = number
  default = 256
}

variable "task_memory" {
  type    = number
  default = 512
}
