variable "project_name" {
  type        = string
  description = "リソース名のプレフィックス"
}

variable "aws_region" {
  type        = string
  description = "デプロイ先リージョン"
}

variable "private_subnet_ids" {
  type        = list(string)
  description = "ECSタスクを配置するプライベートサブネットID（複数）"
}

variable "ecs_security_group_id" {
  type        = string
  description = "ECSタスク用セキュリティグループID"
}

variable "container_name" {
  type        = string
  description = "タスク定義のコンテナ名"
}

variable "container_port" {
  type        = number
  description = "コンテナが使用するポート番号"
  default     = 80
}

variable "ecr_repository_url" {
  type        = string
  description = "ECRリポジトリのURI"
}

variable "task_execution_role_arn" {
  type        = string
  description = "ECS Task Execution ロールのARN"
}

variable "task_role_arn" {
  type        = string
  description = "ECS Task ロールのARN"
}

variable "target_group_blue_arn" {
  type        = string
  description = "Blue Target GroupのARN"
}
