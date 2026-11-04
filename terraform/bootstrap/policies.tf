# ---------------------------------------------------------------------------
# Rol build: solo login a ECR y push/lectura en los dos repositorios
# ---------------------------------------------------------------------------
data "aws_iam_policy_document" "build" {
  statement {
    sid       = "EcrLogin"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"] # GetAuthorizationToken no admite restriccion por recurso
  }

  statement {
    sid = "EcrPushPull"
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:BatchGetImage",
      "ecr:CompleteLayerUpload",
      "ecr:DescribeImageScanFindings",
      "ecr:DescribeImages",
      "ecr:DescribeRepositories",
      "ecr:GetDownloadUrlForLayer",
      "ecr:InitiateLayerUpload",
      "ecr:ListImages",
      "ecr:PutImage",
      "ecr:UploadLayerPart",
    ]
    resources = local.ecr_repo_arns
  }
}

resource "aws_iam_policy" "build" {
  name   = "${var.project_name}-github-build"
  policy = data.aws_iam_policy_document.build.json
}

resource "aws_iam_role_policy_attachment" "build" {
  role       = aws_iam_role.build.name
  policy_arn = aws_iam_policy.build.arn
}

# ---------------------------------------------------------------------------
# Rol deploy: registrar task definitions, actualizar servicios, leer ECR
# ---------------------------------------------------------------------------
#trivy:ignore:AVD-AWS-0342 (PassRole acotado a roles triplepipe-* y a ecs-tasks.amazonaws.com)
data "aws_iam_policy_document" "deploy" {
  statement {
    sid = "EcsLecturaYRegistro"
    actions = [
      "ecs:DeregisterTaskDefinition",
      "ecs:DescribeTaskDefinition",
      "ecs:ListTaskDefinitions",
      "ecs:RegisterTaskDefinition",
    ]
    resources = ["*"] # las acciones de task definition no admiten restriccion por recurso
  }

  statement {
    sid = "EcsDescribe"
    actions = [
      "ecs:DescribeClusters",
      "ecs:DescribeServices",
      "ecs:DescribeTasks",
      "ecs:ListServices",
      "ecs:ListTasks",
    ]
    resources = ["*"]
  }

  statement {
    sid       = "EcsActualizarServicios"
    actions   = ["ecs:UpdateService"]
    resources = ["${local.arn_base}:ecs:${local.region}:${local.account_id}:service/${local.prefix}-cluster/${local.prefix}-*"]
  }

  statement {
    sid       = "EcsEtiquetarTaskDefinition"
    actions   = ["ecs:TagResource"]
    resources = ["${local.arn_base}:ecs:${local.region}:${local.account_id}:task-definition/${local.prefix}-*:*"]
  }

  statement {
    sid = "EcrLecturaImagenes"
    actions = [
      "ecr:BatchGetImage",
      "ecr:DescribeImages",
      "ecr:DescribeRepositories",
      "ecr:ListImages",
    ]
    resources = local.ecr_repo_arns
  }

  statement {
    sid       = "AlbLectura"
    actions   = ["elasticloadbalancing:Describe*"]
    resources = ["*"] # Describe* de elbv2 no admite restriccion por recurso
  }

  statement {
    sid       = "PasarRolesDeEcs"
    actions   = ["iam:PassRole"]
    resources = local.ecs_role_arns

    condition {
      test     = "StringEquals"
      variable = "iam:PassedToService"
      values   = ["ecs-tasks.amazonaws.com"]
    }
  }
}

resource "aws_iam_policy" "deploy" {
  name   = "${var.project_name}-github-deploy"
  policy = data.aws_iam_policy_document.deploy.json
}

resource "aws_iam_role_policy_attachment" "deploy" {
  role       = aws_iam_role.deploy.name
  policy_arn = aws_iam_policy.deploy.arn
}

# ---------------------------------------------------------------------------
# Rol infra: crear y destruir todo lo del modulo raiz. Se divide en tres
# politicas administradas (limite de 6144 caracteres por politica).
# ---------------------------------------------------------------------------

# --- 1) Estado de Terraform + red (EC2) + balanceador (ELBv2) ---------------
data "aws_iam_policy_document" "infra_network" {
  statement {
    sid       = "EstadoListarBucket"
    actions   = ["s3:GetBucketLocation", "s3:ListBucket"]
    resources = [aws_s3_bucket.state.arn]
  }

  statement {
    sid = "EstadoYLockfile"
    # Incluye <key>.tflock (use_lockfile) y los objetos de estado versionados
    actions   = ["s3:DeleteObject", "s3:GetObject", "s3:PutObject"]
    resources = ["${aws_s3_bucket.state.arn}/*"]
  }

  statement {
    sid       = "Ec2Lectura"
    actions   = ["ec2:Describe*", "ec2:GetSecurityGroupsForVpc"]
    resources = ["*"] # Describe* de EC2 no admite restriccion por recurso
  }

  statement {
    sid = "Ec2Red"
    actions = [
      "ec2:AssociateRouteTable",
      "ec2:AttachInternetGateway",
      "ec2:AuthorizeSecurityGroupEgress",
      "ec2:AuthorizeSecurityGroupIngress",
      "ec2:CreateInternetGateway",
      "ec2:CreateRoute",
      "ec2:CreateRouteTable",
      "ec2:CreateSecurityGroup",
      "ec2:CreateSubnet",
      "ec2:CreateTags",
      "ec2:CreateVpc",
      "ec2:DeleteInternetGateway",
      "ec2:DeleteRoute",
      "ec2:DeleteRouteTable",
      "ec2:DeleteSecurityGroup",
      "ec2:DeleteSubnet",
      "ec2:DeleteTags",
      "ec2:DeleteVpc",
      "ec2:DetachInternetGateway",
      "ec2:DisassociateRouteTable",
      "ec2:ModifySecurityGroupRules",
      "ec2:ModifySubnetAttribute",
      "ec2:ModifyVpcAttribute",
      "ec2:ReplaceRoute",
      "ec2:ReplaceRouteTableAssociation",
      "ec2:RevokeSecurityGroupEgress",
      "ec2:RevokeSecurityGroupIngress",
      "ec2:UpdateSecurityGroupRuleDescriptionsEgress",
      "ec2:UpdateSecurityGroupRuleDescriptionsIngress",
    ]
    # Varias acciones de creacion de EC2 no se pueden acotar por nombre; se acota por region.
    resources = ["*"]

    condition {
      test     = "StringEquals"
      variable = "aws:RequestedRegion"
      values   = [local.region]
    }
  }

  statement {
    sid       = "ElbLectura"
    actions   = ["elasticloadbalancing:Describe*"]
    resources = ["*"] # Describe* de elbv2 no admite restriccion por recurso
  }

  statement {
    sid = "ElbGestion"
    actions = [
      "elasticloadbalancing:AddTags",
      "elasticloadbalancing:CreateListener",
      "elasticloadbalancing:CreateLoadBalancer",
      "elasticloadbalancing:CreateRule",
      "elasticloadbalancing:CreateTargetGroup",
      "elasticloadbalancing:DeleteListener",
      "elasticloadbalancing:DeleteLoadBalancer",
      "elasticloadbalancing:DeleteRule",
      "elasticloadbalancing:DeleteTargetGroup",
      "elasticloadbalancing:DeregisterTargets",
      "elasticloadbalancing:ModifyListener",
      "elasticloadbalancing:ModifyLoadBalancerAttributes",
      "elasticloadbalancing:ModifyRule",
      "elasticloadbalancing:ModifyTargetGroup",
      "elasticloadbalancing:ModifyTargetGroupAttributes",
      "elasticloadbalancing:RegisterTargets",
      "elasticloadbalancing:RemoveTags",
      "elasticloadbalancing:SetIpAddressType",
      "elasticloadbalancing:SetRulePriorities",
      "elasticloadbalancing:SetSecurityGroups",
      "elasticloadbalancing:SetSubnets",
    ]
    resources = [
      "${local.arn_base}:elasticloadbalancing:${local.region}:${local.account_id}:loadbalancer/app/${local.prefix}-*/*",
      "${local.arn_base}:elasticloadbalancing:${local.region}:${local.account_id}:targetgroup/${local.prefix}-*/*",
      "${local.arn_base}:elasticloadbalancing:${local.region}:${local.account_id}:listener/app/${local.prefix}-*/*",
      "${local.arn_base}:elasticloadbalancing:${local.region}:${local.account_id}:listener-rule/app/${local.prefix}-*/*",
    ]
  }
}

# --- 2) ECR + ECS + CloudWatch Logs + DynamoDB -------------------------------
data "aws_iam_policy_document" "infra_compute" {
  statement {
    sid = "Ecr"
    actions = [
      "ecr:BatchDeleteImage", # necesario para force_delete en DeleteRepository
      "ecr:BatchGetImage",
      "ecr:CreateRepository",
      "ecr:DeleteLifecyclePolicy",
      "ecr:DeleteRepository",
      "ecr:DeleteRepositoryPolicy",
      "ecr:DescribeImages",
      "ecr:DescribeRepositories",
      "ecr:GetLifecyclePolicy",
      "ecr:GetRepositoryPolicy",
      "ecr:ListImages",
      "ecr:ListTagsForResource",
      "ecr:PutImageScanningConfiguration",
      "ecr:PutImageTagMutability",
      "ecr:PutLifecyclePolicy",
      "ecr:SetRepositoryPolicy",
      "ecr:TagResource",
      "ecr:UntagResource",
    ]
    resources = ["${local.arn_base}:ecr:${local.region}:${local.account_id}:repository/${var.project_name}-*"]
  }

  statement {
    sid = "EcsClusterYServicios"
    actions = [
      "ecs:CreateCluster",
      "ecs:CreateService",
      "ecs:DeleteCluster",
      "ecs:DeleteService",
      "ecs:DescribeClusters",
      "ecs:DescribeServices",
      "ecs:ListTagsForResource",
      "ecs:PutClusterCapacityProviders",
      "ecs:TagResource",
      "ecs:UntagResource",
      "ecs:UpdateCluster",
      "ecs:UpdateClusterSettings",
      "ecs:UpdateService",
    ]
    resources = [
      "${local.arn_base}:ecs:${local.region}:${local.account_id}:cluster/${var.project_name}-*",
      "${local.arn_base}:ecs:${local.region}:${local.account_id}:service/${var.project_name}-*/${var.project_name}-*",
    ]
  }

  statement {
    sid = "EcsTaskDefinitions"
    actions = [
      "ecs:DeleteTaskDefinitions",
      "ecs:DeregisterTaskDefinition",
      "ecs:DescribeTaskDefinition",
      "ecs:ListTaskDefinitions",
      "ecs:RegisterTaskDefinition",
    ]
    resources = ["*"] # las acciones de task definition no admiten restriccion por recurso
  }

  statement {
    sid       = "EcsTareasParaDrenarServicios"
    actions   = ["ecs:DescribeTasks", "ecs:ListTasks", "ecs:StopTask"]
    resources = ["*"]

    condition {
      test     = "ArnLike"
      variable = "ecs:cluster"
      values   = ["${local.arn_base}:ecs:${local.region}:${local.account_id}:cluster/${var.project_name}-*"]
    }
  }

  statement {
    sid = "LogsGrupos"
    actions = [
      "logs:CreateLogGroup",
      "logs:DeleteLogGroup",
      "logs:DeleteRetentionPolicy",
      "logs:ListTagsForResource",
      "logs:ListTagsLogGroup",
      "logs:PutRetentionPolicy",
      "logs:TagLogGroup",
      "logs:TagResource",
      "logs:UntagLogGroup",
      "logs:UntagResource",
    ]
    resources = [
      "${local.arn_base}:logs:${local.region}:${local.account_id}:log-group:/ecs/${var.project_name}-*",
      "${local.arn_base}:logs:${local.region}:${local.account_id}:log-group:/ecs/${var.project_name}-*:*",
    ]
  }

  statement {
    sid       = "LogsLectura"
    actions   = ["logs:DescribeLogGroups"]
    resources = ["*"] # DescribeLogGroups no admite restriccion por recurso
  }

  statement {
    sid = "DynamoDb"
    actions = [
      "dynamodb:CreateTable",
      "dynamodb:DeleteTable",
      "dynamodb:DescribeContinuousBackups",
      "dynamodb:DescribeContributorInsights",
      "dynamodb:DescribeKinesisStreamingDestination",
      "dynamodb:DescribeTable",
      "dynamodb:DescribeTimeToLive",
      "dynamodb:ListTagsOfResource",
      "dynamodb:TagResource",
      "dynamodb:UntagResource",
      "dynamodb:UpdateContinuousBackups",
      "dynamodb:UpdateTable",
      "dynamodb:UpdateTimeToLive",
    ]
    resources = ["${local.arn_base}:dynamodb:${local.region}:${local.account_id}:table/${var.project_name}-*"]
  }
}

# --- 3) IAM (roles de ECS) ----------------------------------------------------
#trivy:ignore:AVD-AWS-0342 (PassRole acotado a roles triplepipe-* y a ecs-tasks.amazonaws.com)
data "aws_iam_policy_document" "infra_iam" {
  # Se acota a triplepipe-<env>-*: los roles de pipeline (triplepipe-github-*) quedan fuera,
  # para que el rol infra no pueda modificarse a si mismo ni a los demas pipelines.
  statement {
    sid = "IamRolesDeEcs"
    actions = [
      "iam:CreateRole",
      "iam:DeleteRole",
      "iam:DeleteRolePolicy",
      "iam:DetachRolePolicy",
      "iam:GetRole",
      "iam:GetRolePolicy",
      "iam:ListAttachedRolePolicies",
      "iam:ListInstanceProfilesForRole",
      "iam:ListRolePolicies",
      "iam:PutRolePolicy",
      "iam:TagRole",
      "iam:UntagRole",
      "iam:UpdateAssumeRolePolicy",
      "iam:UpdateRole",
      "iam:UpdateRoleDescription",
    ]
    resources = ["${local.arn_base}:iam::${local.account_id}:role/${local.prefix}-*"]
  }

  statement {
    sid       = "IamAdjuntarSoloPoliticaGestionadaDeEcs"
    actions   = ["iam:AttachRolePolicy"]
    resources = ["${local.arn_base}:iam::${local.account_id}:role/${local.prefix}-*"]

    condition {
      test     = "ArnEquals"
      variable = "iam:PolicyARN"
      values   = ["${local.arn_base}:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"]
    }
  }

  statement {
    sid       = "IamPassRoleAEcs"
    actions   = ["iam:PassRole"]
    resources = ["${local.arn_base}:iam::${local.account_id}:role/${local.prefix}-*"]

    condition {
      test     = "StringEquals"
      variable = "iam:PassedToService"
      values   = ["ecs-tasks.amazonaws.com"]
    }
  }

  statement {
    sid       = "IamLecturaPoliticaGestionada"
    actions   = ["iam:GetPolicy"]
    resources = ["${local.arn_base}:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"]
  }

  statement {
    sid     = "IamRolesVinculadosAServicios"
    actions = ["iam:CreateServiceLinkedRole"]
    resources = [
      "${local.arn_base}:iam::${local.account_id}:role/aws-service-role/ecs.amazonaws.com/AWSServiceRoleForECS*",
      "${local.arn_base}:iam::${local.account_id}:role/aws-service-role/elasticloadbalancing.amazonaws.com/AWSServiceRoleForElasticLoadBalancing*",
    ]

    condition {
      test     = "StringEquals"
      variable = "iam:AWSServiceName"
      values   = ["ecs.amazonaws.com", "elasticloadbalancing.amazonaws.com"]
    }
  }
}

resource "aws_iam_policy" "infra_network" {
  name   = "${var.project_name}-github-infra-network"
  policy = data.aws_iam_policy_document.infra_network.json
}

resource "aws_iam_policy" "infra_compute" {
  name   = "${var.project_name}-github-infra-compute"
  policy = data.aws_iam_policy_document.infra_compute.json
}

resource "aws_iam_policy" "infra_iam" {
  name   = "${var.project_name}-github-infra-iam"
  policy = data.aws_iam_policy_document.infra_iam.json
}

resource "aws_iam_role_policy_attachment" "infra" {
  for_each = {
    network = aws_iam_policy.infra_network.arn
    compute = aws_iam_policy.infra_compute.arn
    iam     = aws_iam_policy.infra_iam.arn
  }

  role       = aws_iam_role.infra.name
  policy_arn = each.value
}
