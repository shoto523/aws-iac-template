output "repository_name" {
  description = "CodeCommitリポジトリ名"
  value       = aws_codecommit_repository.main.repository_name
}

output "repository_arn" {
  description = "CodeCommitリポジトリのARN"
  value       = aws_codecommit_repository.main.arn
}

output "clone_url_ssh" {
  description = "SSH接続用クローンURL"
  value       = aws_codecommit_repository.main.clone_url_ssh
}

output "clone_url_http" {
  description = "HTTPS接続用クローンURL"
  value       = aws_codecommit_repository.main.clone_url_http
}
