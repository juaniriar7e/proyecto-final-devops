data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}

locals {
  account_id = data.aws_caller_identity.current.account_id
  partition  = data.aws_partition.current.partition
  prefix     = "${var.project_name}-${var.environment}"

  state_bucket_name = "${var.project_name}-tfstate-${local.account_id}"

  oidc_host = "token.actions.githubusercontent.com"
  oidc_arn  = var.create_github_oidc_provider ? aws_iam_openid_connect_provider.github[0].arn : data.aws_iam_openid_connect_provider.github[0].arn

  # Subjects permitidos: solo la rama main y el environment production del repo.
  allowed_subjects = [
    "repo:${var.github_repository}:ref:refs/heads/main",
    "repo:${var.github_repository}:environment:production",
  ]

  arn_base = "arn:${local.partition}"
  region   = var.aws_region

  ecr_repo_arns = [
    "${local.arn_base}:ecr:${local.region}:${local.account_id}:repository/${local.prefix}-frontend",
    "${local.arn_base}:ecr:${local.region}:${local.account_id}:repository/${local.prefix}-backend",
  ]

  # Roles de ECS que el pipeline 3 puede pasar a las tareas.
  ecs_role_arns = [
    "${local.arn_base}:iam::${local.account_id}:role/${local.prefix}-ecs-execution",
    "${local.arn_base}:iam::${local.account_id}:role/${local.prefix}-backend-task",
    "${local.arn_base}:iam::${local.account_id}:role/${local.prefix}-frontend-task",
  ]
}

# ---------------------------------------------------------------------------
# Bucket de estado de Terraform (versionado, cifrado, privado, bloqueo por .tflock)
# ---------------------------------------------------------------------------
resource "aws_s3_bucket" "state" {
  bucket = local.state_bucket_name
}

resource "aws_s3_bucket_versioning" "state" {
  bucket = aws_s3_bucket.state.id

  versioning_configuration {
    status = "Enabled"
  }
}

#trivy:ignore:AVD-AWS-0132 (SSE-S3 es suficiente para el estado; evita depender de KMS)
resource "aws_s3_bucket_server_side_encryption_configuration" "state" {
  bucket = aws_s3_bucket.state.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "state" {
  bucket = aws_s3_bucket.state.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "state" {
  bucket = aws_s3_bucket.state.id

  rule {
    id     = "expirar-versiones-antiguas"
    status = "Enabled"

    filter {}

    noncurrent_version_expiration {
      noncurrent_days = 90
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}

data "aws_iam_policy_document" "state_bucket" {
  statement {
    sid       = "DenegarTransporteSinTLS"
    effect    = "Deny"
    actions   = ["s3:*"]
    resources = [aws_s3_bucket.state.arn, "${aws_s3_bucket.state.arn}/*"]

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

resource "aws_s3_bucket_policy" "state" {
  bucket = aws_s3_bucket.state.id
  policy = data.aws_iam_policy_document.state_bucket.json

  depends_on = [aws_s3_bucket_public_access_block.state]
}

# ---------------------------------------------------------------------------
# Proveedor OIDC de GitHub Actions
# ---------------------------------------------------------------------------
resource "aws_iam_openid_connect_provider" "github" {
  count = var.create_github_oidc_provider ? 1 : 0

  url            = "https://${local.oidc_host}"
  client_id_list = ["sts.amazonaws.com"]
  # AWS valida el certificado con su propia CA raíz; el valor se conserva por compatibilidad.
  thumbprint_list = ["6938fd4d98bab03faadb97b34396831e3780aea1"]
}

data "aws_iam_openid_connect_provider" "github" {
  count = var.create_github_oidc_provider ? 0 : 1

  url = "https://${local.oidc_host}"
}

data "aws_iam_policy_document" "trust" {
  statement {
    sid     = "GitHubOIDC"
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [local.oidc_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.oidc_host}:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.oidc_host}:sub"
      values   = local.allowed_subjects
    }
  }
}

resource "aws_iam_role" "infra" {
  name                 = "${var.project_name}-github-infra"
  description          = "Pipeline 1: Terraform de la infraestructura (OIDC GitHub)"
  assume_role_policy   = data.aws_iam_policy_document.trust.json
  max_session_duration = 3600
}

resource "aws_iam_role" "build" {
  name                 = "${var.project_name}-github-build"
  description          = "Pipeline 2: build y push de imagenes a ECR (OIDC GitHub)"
  assume_role_policy   = data.aws_iam_policy_document.trust.json
  max_session_duration = 3600
}

resource "aws_iam_role" "deploy" {
  name                 = "${var.project_name}-github-deploy"
  description          = "Pipeline 3: despliegue en ECS (OIDC GitHub)"
  assume_role_policy   = data.aws_iam_policy_document.trust.json
  max_session_duration = 3600
}
