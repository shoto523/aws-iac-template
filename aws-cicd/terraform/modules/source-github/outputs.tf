output "connection_arn" {
  description = "CodeStar Connections の ARN（CodePipelineで使用）"
  value       = aws_codestarconnections_connection.github.arn
}

output "connection_name" {
  description = "CodeStar Connections の名前"
  value       = aws_codestarconnections_connection.github.name
}

output "connection_status" {
  description = "接続ステータス（PENDING → 手動承認後 AVAILABLE）"
  value       = aws_codestarconnections_connection.github.connection_status
}
