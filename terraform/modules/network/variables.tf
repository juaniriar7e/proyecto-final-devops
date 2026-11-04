variable "name" {
  description = "Prefijo de nombres."
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR de la VPC."
  type        = string
}

variable "az_count" {
  description = "Número de zonas de disponibilidad."
  type        = number
  default     = 2
}
