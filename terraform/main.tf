data "aws_caller_identity" "current" {}

locals {
  prefix = "${var.project_name}-${var.environment}"
}

module "network" {
  source = "./modules/network"

  name     = local.prefix
  vpc_cidr = var.vpc_cidr
  az_count = 2
}

module "ecr" {
  source = "./modules/ecr"

  repository_names = {
    frontend = "${local.prefix}-frontend"
    backend  = "${local.prefix}-backend"
  }
}

module "data" {
  source = "./modules/data"

  table_name = "${local.prefix}-tasks"
}

module "alb" {
  source = "./modules/alb"

  name              = local.prefix
  vpc_id            = module.network.vpc_id
  subnet_ids        = module.network.public_subnet_ids
  security_group_id = module.network.alb_security_group_id
}

module "ecs" {
  source = "./modules/ecs"

  name                = local.prefix
  aws_region          = var.aws_region
  subnet_ids          = module.network.public_subnet_ids
  security_group_id   = module.network.tasks_security_group_id
  repository_urls     = module.ecr.repository_urls
  target_group_arns   = module.alb.target_group_arns
  dynamodb_table_name = module.data.table_name
  dynamodb_table_arn  = module.data.table_arn
  log_retention_days  = var.log_retention_days
  task_cpu            = var.task_cpu
  task_memory         = var.task_memory

  # Los target groups deben estar asociados a un listener antes de crear los servicios.
  depends_on = [module.alb]
}
