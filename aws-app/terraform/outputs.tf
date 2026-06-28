output "ecs_cluster_name" {
  description = "ECSクラスター名（aws-cicdのパラメータに渡す）"
  value       = module.ecs.ecs_cluster_name
}

output "ecs_service_name" {
  description = "ECSサービス名（aws-cicdのパラメータに渡す）"
  value       = module.ecs.ecs_service_name
}

output "codedeploy_app_name" {
  description = "CodeDeployアプリ名（aws-cicdのパラメータに渡す）"
  value       = module.codedeploy.codedeploy_app_name
}

output "codedeploy_group_name" {
  description = "CodeDeployデプロイグループ名（aws-cicdのパラメータに渡す）"
  value       = module.codedeploy.codedeploy_group_name
}

output "alb_dns_name" {
  description = "ALBのDNS名（アプリへのアクセスURL）"
  value       = module.alb.alb_dns_name
}
