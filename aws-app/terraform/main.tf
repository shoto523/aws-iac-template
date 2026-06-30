module "iam" {
  source       = "./modules/iam"
  project_name = var.project_name
}

module "alb" {
  source                = "./modules/alb"
  project_name          = var.project_name
  vpc_id                = var.vpc_id
  public_subnet_ids     = var.public_subnet_ids
  alb_security_group_id = var.alb_security_group_id
  container_port        = var.container_port
}

module "ecs" {
  source                    = "./modules/ecs"
  project_name              = var.project_name
  aws_region                = var.aws_region
  public_subnet_ids         = var.public_subnet_ids
  ecs_security_group_id     = var.ecs_security_group_id
  container_name            = var.container_name
  container_port            = var.container_port
  ecr_repository_url        = var.ecr_repository_url
  task_execution_role_arn   = module.iam.task_execution_role_arn
  task_role_arn             = module.iam.task_role_arn
  target_group_blue_arn     = module.alb.target_group_blue_arn
}

module "codedeploy" {
  source                  = "./modules/codedeploy"
  project_name            = var.project_name
  codedeploy_role_arn     = module.iam.codedeploy_role_arn
  ecs_cluster_name        = module.ecs.ecs_cluster_name
  ecs_service_name        = module.ecs.ecs_service_name
  target_group_blue_name  = module.alb.target_group_blue_name
  target_group_green_name = module.alb.target_group_green_name
  listener_prod_arn       = module.alb.listener_prod_arn
  listener_test_arn       = module.alb.listener_test_arn
}
