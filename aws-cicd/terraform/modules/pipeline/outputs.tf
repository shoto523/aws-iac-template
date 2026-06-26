output "pipeline_arn" {
  description = "CodePipelineのARN"
  value       = aws_codepipeline.main.arn
}

output "pipeline_name" {
  description = "CodePipelineの名前"
  value       = aws_codepipeline.main.name
}

output "artifact_bucket_name" {
  description = "S3アーティファクトバケット名"
  value       = aws_s3_bucket.artifact.bucket
}

output "artifact_bucket_arn" {
  description = "S3アーティファクトバケットのARN"
  value       = aws_s3_bucket.artifact.arn
}
