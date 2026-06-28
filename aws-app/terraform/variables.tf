variable "project_name" {
  type        = string
  description = "リソース名のプレフィックス"
}

variable "aws_region" {
  type        = string
  description = "デプロイ先リージョン"
  default     = "ap-northeast-1"
}

# ネットワーク（前提条件）
variable "vpc_id" {
  type        = string
  description = "ECS・ALBを配置するVPC ID"
}

variable "public_subnet_ids" {
  type        = list(string)
  description = "ALBを配置するパブリックサブネットID（複数）"
}

variable "private_subnet_ids" {
  type        = list(string)
  description = "ECSタスクを配置するプライベートサブネットID（複数）"
}

variable "alb_security_group_id" {
  type        = string
  description = "ALB用セキュリティグループID"
}

variable "ecs_security_group_id" {
  type        = string
  description = "ECSタスク用セキュリティグループID"
}

# コンテナ
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
  description = "ECRリポジトリのURI（aws-cicdの出力値）"
}
