resource "aws_codecommit_repository" "main" {
  repository_name = var.repository_name
  description     = var.description != "" ? var.description : "${var.project_name} source repository"

  tags = {
    Project = var.project_name
  }
}
