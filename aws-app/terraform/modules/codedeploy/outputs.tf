output "codedeploy_app_name" {
  description = "CodeDeployアプリ名"
  value       = aws_codedeploy_app.main.name
}

output "codedeploy_group_name" {
  description = "CodeDeployデプロイグループ名"
  value       = aws_codedeploy_deployment_group.main.deployment_group_name
}
