# ----------------------------------------
# CodeDeploy Application
# ----------------------------------------
resource "aws_codedeploy_app" "main" {
  name             = "${var.project_name}-deploy"
  compute_platform = "ECS"

  tags = { Project = var.project_name }
}

# ----------------------------------------
# CodeDeploy Deployment Group
# ----------------------------------------
resource "aws_codedeploy_deployment_group" "main" {
  app_name               = aws_codedeploy_app.main.name
  deployment_group_name  = "${var.project_name}-deploy-group"
  service_role_arn       = var.codedeploy_role_arn
  deployment_config_name = "CodeDeployDefault.ECSAllAtOnce"

  deployment_style {
    deployment_type   = "BLUE_GREEN"
    deployment_option = "WITH_TRAFFIC_CONTROL"
  }

  ecs_service {
    cluster_name = var.ecs_cluster_name
    service_name = var.ecs_service_name
  }

  load_balancer_info {
    target_group_pair_info {
      prod_traffic_route {
        listener_arns = [var.listener_prod_arn]
      }
      test_traffic_route {
        listener_arns = [var.listener_test_arn]
      }
      target_group {
        name = var.target_group_blue_name
      }
      target_group {
        name = var.target_group_green_name
      }
    }
  }

  blue_green_deployment_config {
    deployment_ready_option {
      action_on_timeout = "CONTINUE_DEPLOYMENT"
    }
    terminate_blue_instances_on_deployment_success {
      action                           = "TERMINATE"
      termination_wait_time_in_minutes = 5
    }
  }

  tags = { Project = var.project_name }
}
