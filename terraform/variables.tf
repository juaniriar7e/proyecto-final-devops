variable "aws_region" {
  description = "Región de AWS."
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Nombre del proyecto."
  type        = string
  default     = "triplepipe"
}

variable "environment" {
  description = "Ambiente."
  type        = string
  default     = "demo"
}

variable "vpc_cidr" {
  description = "CIDR de la VPC."
  type        = string
  default     = "10.20.0.0/16"
}

variable "log_retention_days" {
  description = "Retención de los logs en CloudWatch."
  type        = number
  default     = 7
}

variable "task_cpu" {
  description = "CPU de cada tarea Fargate."
  type        = number
  default     = 256
}

variable "task_memory" {
  description = "Memoria (MB) de cada tarea Fargate."
  type        = number
  default     = 512
}
