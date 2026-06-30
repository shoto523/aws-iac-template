output "ecr_repository_url" {
  description = "ECRリポジトリのURI（aws-appのtaskdef.jsonで使用）"
  value       = module.ecr.repository_url
}

output "pipeline_name" {
  description = "CodePipelineの名前"
  value       = module.pipeline.pipeline_name
}

output "artifact_bucket_name" {
  description = "S3アーティファクトバケット名"
  value       = aws_s3_bucket.artifact.bucket
}
