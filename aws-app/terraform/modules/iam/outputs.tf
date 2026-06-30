output "task_execution_role_arn" {
  description = "ECS Task Execution ロールのARN"
  value       = aws_iam_role.task_execution.arn
}

output "task_role_arn" {
  description = "ECS Task ロールのARN"
  value       = aws_iam_role.task.arn
}

output "codedeploy_role_arn" {
  description = "CodeDeploy 実行ロールのARN"
  value       = aws_iam_role.codedeploy.arn
}
