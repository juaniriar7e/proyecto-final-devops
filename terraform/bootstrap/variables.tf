variable "github_repository" {
  description = "Repositorio de GitHub con formato owner/repo autorizado a asumir los roles."
  type        = string

  validation {
    condition     = can(regex("^[A-Za-z0-9-_.]+/[A-Za-z0-9-_.]+$", var.github_repository))
    error_message = "github_repository debe tener el formato owner/repo."
  }
}

variable "aws_region" {
  description = "Región de AWS."
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Nombre del proyecto (contrato: triplepipe)."
  type        = string
  default     = "triplepipe"
}

variable "environment" {
  description = "Ambiente (contrato: demo)."
  type        = string
  default     = "demo"
}

variable "create_github_oidc_provider" {
  description = "Crear el proveedor OIDC de GitHub. Poner false si la cuenta ya tiene uno (solo puede existir uno por URL)."
  type        = bool
  default     = true
}
