output "codepipeline_role_arn" {
  description = "CodePipeline実行ロールのARN"
  value       = aws_iam_role.codepipeline.arn
}

output "codebuild_role_arn" {
  description = "CodeBuild実行ロールのARN"
  value       = aws_iam_role.codebuild.arn
}

output "eventbridge_role_arn" {
  description = "EventBridge実行ロールのARN（CodeCommit版のみ。GitHub版は空文字）"
  value       = var.source_type == "codecommit" ? aws_iam_role.eventbridge[0].arn : ""
}
