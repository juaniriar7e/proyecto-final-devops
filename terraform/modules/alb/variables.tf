variable "name" {
  description = "Prefijo de nombres (el ALB se llama <name>-alb)."
  type        = string
}

variable "vpc_id" {
  type = string
}

variable "subnet_ids" {
  type = list(string)
}

variable "security_group_id" {
  type = string
}

variable "frontend_port" {
  type    = number
  default = 8080
}

variable "backend_port" {
  type    = number
  default = 8000
}
