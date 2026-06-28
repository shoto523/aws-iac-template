variable "project_name" {
  type        = string
  description = "リソース名のプレフィックス"
}

variable "vpc_id" {
  type        = string
  description = "ALBを配置するVPC ID"
}

variable "public_subnet_ids" {
  type        = list(string)
  description = "ALBを配置するパブリックサブネットID（複数）"
}

variable "alb_security_group_id" {
  type        = string
  description = "ALB用セキュリティグループID"
}

variable "container_port" {
  type        = number
  description = "コンテナが使用するポート番号"
  default     = 80
}
