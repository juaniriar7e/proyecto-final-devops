variable "repository_names" {
  description = "Mapa clave lógica => nombre del repositorio."
  type        = map(string)
}

variable "keep_last_images" {
  description = "Número de imágenes que conserva el lifecycle."
  type        = number
  default     = 10
}
