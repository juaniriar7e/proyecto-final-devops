data "aws_caller_identity" "current" {}

locals {
  services = {
    frontend = {
      port = 8080
      env  = [{ name = "APP_VERSION", value = "bootstrap" }]
    }
    backend = {
      port = 8000
      env = [
        { name = "TASKS_TABLE", value = var.dynamodb_table_name },
        { name = "AWS_REGION", value = var.aws_region },
        { name = "APP_VERSION", value = "bootstrap" },
      ]
    }
  }
}

resource "aws_ecs_cluster" "this" {
  name = "${var.name}-cluster"

  setting {
    name  = "containerInsights"
    value = "disabled"
  }
}

resource "aws_cloudwatch_log_group" "this" {
  for_each = local.services

  name              = "/ecs/${var.name}-${each.key}"
  retention_in_days = var.log_retention_days
}

# --- Roles de ECS ---------------------------------------------------------------
data "aws_iam_policy_document" "ecs_tasks_assume" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }
  }
}

resource "aws_iam_role" "execution" {
  name               = "${var.name}-ecs-execution"
  assume_role_policy = data.aws_iam_policy_document.ecs_tasks_assume.json
}

resource "aws_iam_role_policy_attachment" "execution" {
  role       = aws_iam_role.execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_iam_role" "task" {
  for_each = local.services

  name               = "${var.name}-${each.key}-task"
  assume_role_policy = data.aws_iam_policy_document.ecs_tasks_assume.json
}

data "aws_iam_policy_document" "backend_dynamodb" {
  statement {
    actions = [
      "dynamodb:DeleteItem",
      "dynamodb:GetItem",
      "dynamodb:PutItem",
      "dynamodb:Scan",
      "dynamodb:UpdateItem",
    ]
    resources = [var.dynamodb_table_arn]
  }
}

resource "aws_iam_role_policy" "backend_dynamodb" {
  name   = "tasks-table"
  role   = aws_iam_role.task["backend"].id
  policy = data.aws_iam_policy_document.backend_dynamodb.json
}

# --- Task definitions iniciales ---------------------------------------------------
# La imagen ":bootstrap" no existe: por eso los servicios nacen con desired_count = 0.
# El pipeline 3 registra las revisiones reales.
resource "aws_ecs_task_definition" "this" {
  for_each = local.services

  family                   = "${var.name}-${each.key}"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = var.task_cpu
  memory                   = var.task_memory
  execution_role_arn       = aws_iam_role.execution.arn
  task_role_arn            = aws_iam_role.task[each.key].arn

  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = "X86_64"
  }

  container_definitions = jsonencode([{
    name      = each.key
    image     = "${var.repository_urls[each.key]}:bootstrap"
    essential = true

    portMappings = [{
      containerPort = each.value.port
      protocol      = "tcp"
    }]

    environment = each.value.env

    logConfiguration = {
      logDriver = "awslogs"
      options = {
        awslogs-group         = aws_cloudwatch_log_group.this[each.key].name
        awslogs-region        = var.aws_region
        awslogs-stream-prefix = each.key
      }
    }
  }])
}

# --- Servicios ----------------------------------------------------------------------
resource "aws_ecs_service" "this" {
  for_each = local.services

  name            = "${var.name}-${each.key}"
  cluster         = aws_ecs_cluster.this.id
  task_definition = aws_ecs_task_definition.this[each.key].arn
  launch_type     = "FARGATE"
  desired_count   = 0

  deployment_minimum_healthy_percent = 100
  deployment_maximum_percent         = 200
  health_check_grace_period_seconds  = 30

  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  network_configuration {
    subnets          = var.subnet_ids
    security_groups  = [var.security_group_id]
    assign_public_ip = true # sin NAT: necesario para descargar la imagen de ECR
  }

  load_balancer {
    target_group_arn = var.target_group_arns[each.key]
    container_name   = each.key
    container_port   = each.value.port
  }

  # El pipeline 3 es dueño de la versión en ejecución.
  lifecycle {
    ignore_changes = [task_definition, desired_count]
  }
}
