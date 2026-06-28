data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

locals {
  account_id = data.aws_caller_identity.current.account_id
  region     = data.aws_region.current.name
}

# ----------------------------------------
# ECS Task Execution ロール
# ----------------------------------------
resource "aws_iam_role" "task_execution" {
  name = "${var.project_name}-ecs-task-execution-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = { Project = var.project_name }
}

resource "aws_iam_role_policy" "task_execution_ecr_auth" {
  name = "ecr-auth"
  role = aws_iam_role.task_execution.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = "ecr:GetAuthorizationToken"
      Resource = "*"
    }]
  })
}

resource "aws_iam_role_policy" "task_execution_ecr_image" {
  name = "ecr-image"
  role = aws_iam_role.task_execution.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "ecr:BatchGetImage",
        "ecr:GetDownloadUrlForLayer",
        "ecr:BatchCheckLayerAvailability"
      ]
      Resource = "arn:aws:ecr:${local.region}:${local.account_id}:repository/${var.project_name}"
    }]
  })
}

resource "aws_iam_role_policy" "task_execution_logs" {
  name = "cloudwatch-logs"
  role = aws_iam_role.task_execution.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents"
      ]
      Resource = "arn:aws:logs:${local.region}:${local.account_id}:log-group:/ecs/${var.project_name}*"
    }]
  })
}

# ----------------------------------------
# ECS Task ロール（アプリが使用するロール）
# ----------------------------------------
resource "aws_iam_role" "task" {
  name = "${var.project_name}-ecs-task-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = { Project = var.project_name }
}

# ----------------------------------------
# CodeDeploy 実行ロール
# ----------------------------------------
resource "aws_iam_role" "codedeploy" {
  name = "${var.project_name}-codedeploy-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "codedeploy.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = { Project = var.project_name }
}

resource "aws_iam_role_policy" "codedeploy_ecs" {
  name = "ecs"
  role = aws_iam_role.codedeploy.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "ecs:DescribeServices",
        "ecs:UpdateService",
        "ecs:RegisterTaskDefinition",
        "ecs:DescribeTaskDefinition",
        "ecs:CreateTaskSet",
        "ecs:UpdateServicePrimaryTaskSet",
        "ecs:DeleteTaskSet"
      ]
      Resource = "*"
    }]
  })
}

resource "aws_iam_role_policy" "codedeploy_alb" {
  name = "alb"
  role = aws_iam_role.codedeploy.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "elasticloadbalancing:DescribeTargetGroups",
        "elasticloadbalancing:DescribeListeners",
        "elasticloadbalancing:DescribeRules",
        "elasticloadbalancing:ModifyListener",
        "elasticloadbalancing:ModifyRule"
      ]
      Resource = "*"
    }]
  })
}

resource "aws_iam_role_policy" "codedeploy_passrole" {
  name = "passrole"
  role = aws_iam_role.codedeploy.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = "iam:PassRole"
      Resource = "*"
      Condition = {
        StringEqualsIfExists = {
          "iam:PassedToService" = "ecs-tasks.amazonaws.com"
        }
      }
    }]
  })
}

resource "aws_iam_role_policy" "codedeploy_s3" {
  name = "s3-artifact"
  role = aws_iam_role.codedeploy.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = "s3:GetObject"
      Resource = "arn:aws:s3:::*-pipeline-artifacts-*/*"
    }]
  })
}
