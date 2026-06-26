variable "project_name" {
  type        = string
  description = "リソース名のプレフィックス"
}

variable "aws_region" {
  type        = string
  description = "デプロイ先リージョン"
}

variable "source_type" {
  type        = string
  description = "ソースリポジトリ種別: codecommit または github"
}

# CodeCommit版のみ
variable "codecommit_repo_name" {
  type    = string
  default = ""
}

variable "codecommit_repo_arn" {
  type    = string
  default = ""
}

variable "codecommit_branch" {
  type    = string
  default = "main"
}

# GitHub版のみ
variable "connection_arn" {
  type    = string
  default = ""
}

variable "github_owner" {
  type    = string
  default = ""
}

variable "github_repo" {
  type    = string
  default = ""
}

variable "github_branch" {
  type    = string
  default = "main"
}

# 共通
variable "ecr_repository_url" {
  type        = string
  description = "ECRリポジトリのURI"
}

variable "codepipeline_role_arn" {
  type        = string
  description = "CodePipeline実行ロールのARN"
}

variable "codebuild_role_arn" {
  type        = string
  description = "CodeBuild実行ロールのARN"
}

variable "eventbridge_role_arn" {
  type        = string
  description = "EventBridge実行ロールのARN（CodeCommit版のみ）"
  default     = ""
}

# アプリ参照値
variable "ecs_cluster_name" {
  type    = string
  default = ""
}

variable "ecs_service_name" {
  type    = string
  default = ""
}

variable "codedeploy_app_name" {
  type    = string
  default = ""
}

variable "codedeploy_group_name" {
  type    = string
  default = ""
}
