output "repository_url" {
  description = "ECRリポジトリのURI"
  value       = aws_ecr_repository.main.repository_url
}

output "repository_arn" {
  description = "ECRリポジトリのARN"
  value       = aws_ecr_repository.main.arn
}

output "repository_name" {
  description = "ECRリポジトリ名"
  value       = aws_ecr_repository.main.name
}
