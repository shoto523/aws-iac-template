variable "project_name" {
  type        = string
  description = "リソース名のプレフィックス"
}

variable "repository_name" {
  type        = string
  description = "CodeCommitリポジトリ名"
}

variable "description" {
  type        = string
  description = "リポジトリの説明"
  default     = ""
}
