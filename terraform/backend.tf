# Backend S3 parcial: bucket y región se pasan con
#   terraform init -backend-config=backend.hcl
# (ver backend.hcl.example). El bloqueo usa un archivo .tflock en el mismo bucket.
terraform {
  backend "s3" {
    key          = "demo/terraform.tfstate"
    encrypt      = true
    use_lockfile = true
  }
}
