variable "project_name" {
  type        = string
  description = "リソース名のプレフィックス"
}

variable "source_type" {
  type        = string
  description = "ソースリポジトリ種別: codecommit または github"
}

variable "artifact_bucket_arn" {
  type        = string
  description = "S3アーティファクトバケットのARN"
}

variable "ecr_repository_arn" {
  type        = string
  description = "ECRリポジトリのARN"
}

variable "codecommit_repo_arn" {
  type        = string
  description = "CodeCommitリポジトリのARN（CodeCommit版のみ）"
  default     = ""
}

variable "connection_arn" {
  type        = string
  description = "CodeStar ConnectionsのARN（GitHub版のみ）"
  default     = ""
}
