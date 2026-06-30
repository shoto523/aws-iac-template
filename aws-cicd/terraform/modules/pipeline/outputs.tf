output "pipeline_arn" {
  description = "CodePipelineのARN"
  value       = aws_codepipeline.main.arn
}

output "pipeline_name" {
  description = "CodePipelineの名前"
  value       = aws_codepipeline.main.name
}
