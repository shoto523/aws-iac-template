variable "project_name" {
  type        = string
  description = "リソース名のプレフィックス"
}

variable "codedeploy_role_arn" {
  type        = string
  description = "CodeDeploy 実行ロールのARN"
}

variable "ecs_cluster_name" {
  type        = string
  description = "デプロイ対象のECSクラスター名"
}

variable "ecs_service_name" {
  type        = string
  description = "デプロイ対象のECSサービス名"
}

variable "target_group_blue_name" {
  type        = string
  description = "Blue Target Groupの名前"
}

variable "target_group_green_name" {
  type        = string
  description = "Green Target Groupの名前"
}

variable "listener_prod_arn" {
  type        = string
  description = "本番リスナー（:80）のARN"
}

variable "listener_test_arn" {
  type        = string
  description = "テストリスナー（:8080）のARN"
}
