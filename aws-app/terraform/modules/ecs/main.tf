# ----------------------------------------
# CloudWatch Logs（ECSタスクログ）
# ----------------------------------------
resource "aws_cloudwatch_log_group" "ecs" {
  name              = "/ecs/${var.project_name}"
  retention_in_days = 30

  tags = { Project = var.project_name }
}

# ----------------------------------------
# ECS Cluster
# ----------------------------------------
resource "aws_ecs_cluster" "main" {
  name = "${var.project_name}-cluster"

  tags = { Project = var.project_name }
}

# ----------------------------------------
# ECS Task Definition
# ----------------------------------------
resource "aws_ecs_task_definition" "main" {
  family                   = var.project_name
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "256"
  memory                   = "512"
  execution_role_arn       = var.task_execution_role_arn
  task_role_arn            = var.task_role_arn

  container_definitions = jsonencode([
    {
      name      = var.container_name
      image     = "${var.ecr_repository_url}:latest"
      essential = true
      portMappings = [
        {
          containerPort = var.container_port
          protocol      = "tcp"
        }
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.ecs.name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "ecs"
        }
      }
    }
  ])

  tags = { Project = var.project_name }
}

# ----------------------------------------
# ECS Service
# ----------------------------------------
resource "aws_ecs_service" "main" {
  name            = "${var.project_name}-service"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.main.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  deployment_controller {
    type = "CODE_DEPLOY"
  }

  network_configuration {
    subnets          = var.private_subnet_ids
    security_groups  = [var.ecs_security_group_id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = var.target_group_blue_arn
    container_name   = var.container_name
    container_port   = var.container_port
  }

  # CodeDeployがタスク定義とロードバランサーを管理するため無視する
  lifecycle {
    ignore_changes = [task_definition, load_balancer]
  }

  tags = { Project = var.project_name }
}
