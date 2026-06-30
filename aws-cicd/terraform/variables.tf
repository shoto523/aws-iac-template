variable "project_name" {
  type        = string
  description = "リソース名のプレフィックス"
}

variable "aws_region" {
  type        = string
  description = "デプロイ先リージョン"
  default     = "ap-northeast-1"
}

variable "source_type" {
  type        = string
  description = "ソースリポジトリ種別: codecommit または github"
  validation {
    condition     = contains(["codecommit", "github"], var.source_type)
    error_message = "source_type は 'codecommit' または 'github' を指定してください。"
  }
}

# CodeCommit版のみ
variable "codecommit_branch" {
  type        = string
  description = "トリガー対象ブランチ（CodeCommit版）"
  default     = "main"
}

# GitHub版のみ
variable "github_owner" {
  type        = string
  description = "GitHubリポジトリのオーナー名（GitHub版）"
  default     = ""
}

variable "github_repo" {
  type        = string
  description = "GitHubリポジトリ名（GitHub版）"
  default     = ""
}

variable "github_branch" {
  type        = string
  description = "トリガー対象ブランチ（GitHub版）"
  default     = "main"
}

# アプリ参照値（aws-app の出力値）
variable "task_execution_role_arn" {
  type        = string
  description = "ECS Task Execution ロールのARN（aws-appの出力値）"
  default     = ""
}

variable "ecs_cluster_name" {
  type        = string
  description = "デプロイ先ECSクラスター名（aws-appの出力値）"
  default     = ""
}

variable "ecs_service_name" {
  type        = string
  description = "デプロイ先ECSサービス名（aws-appの出力値）"
  default     = ""
}

variable "codedeploy_app_name" {
  type        = string
  description = "CodeDeployアプリ名（aws-appの出力値）"
  default     = ""
}

variable "codedeploy_group_name" {
  type        = string
  description = "CodeDeployデプロイグループ名（aws-appの出力値）"
  default     = ""
}
