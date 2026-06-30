data "aws_caller_identity" "current" {}

# ----------------------------------------
# S3 アーティファクトバケット（rootで定義してIAMとPipelineの循環依存を解消）
# ----------------------------------------
resource "aws_s3_bucket" "artifact" {
  bucket        = "${var.project_name}-pipeline-artifacts-${data.aws_caller_identity.current.account_id}"
  force_destroy = true
  tags          = { Project = var.project_name }
}

resource "aws_s3_bucket_versioning" "artifact" {
  bucket = aws_s3_bucket.artifact.id
  versioning_configuration { status = "Enabled" }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "artifact" {
  bucket = aws_s3_bucket.artifact.id
  rule {
    apply_server_side_encryption_by_default { sse_algorithm = "AES256" }
  }
}

resource "aws_s3_bucket_public_access_block" "artifact" {
  bucket                  = aws_s3_bucket.artifact.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# ----------------------------------------
# モジュール
# ----------------------------------------
module "ecr" {
  source          = "./modules/ecr"
  project_name    = var.project_name
  repository_name = var.project_name
}

module "source_codecommit" {
  count           = var.source_type == "codecommit" ? 1 : 0
  source          = "./modules/source-codecommit"
  project_name    = var.project_name
  repository_name = var.project_name
}

module "source_github" {
  count        = var.source_type == "github" ? 1 : 0
  source       = "./modules/source-github"
  project_name = var.project_name
}

module "iam" {
  source              = "./modules/iam"
  project_name        = var.project_name
  source_type         = var.source_type
  artifact_bucket_arn = aws_s3_bucket.artifact.arn
  ecr_repository_arn  = module.ecr.repository_arn
  codecommit_repo_arn = var.source_type == "codecommit" ? module.source_codecommit[0].repository_arn : ""
  connection_arn      = var.source_type == "github" ? module.source_github[0].connection_arn : ""
}

module "pipeline" {
  source       = "./modules/pipeline"
  project_name = var.project_name
  aws_region   = var.aws_region

  source_type = var.source_type

  codecommit_repo_name = var.source_type == "codecommit" ? module.source_codecommit[0].repository_name : ""
  codecommit_repo_arn  = var.source_type == "codecommit" ? module.source_codecommit[0].repository_arn : ""
  codecommit_branch    = var.codecommit_branch

  connection_arn = var.source_type == "github" ? module.source_github[0].connection_arn : ""
  github_owner   = var.github_owner
  github_repo    = var.github_repo
  github_branch  = var.github_branch

  artifact_bucket_name = aws_s3_bucket.artifact.bucket
  artifact_bucket_arn  = aws_s3_bucket.artifact.arn

  ecr_repository_url = module.ecr.repository_url

  codepipeline_role_arn = module.iam.codepipeline_role_arn
  codebuild_role_arn    = module.iam.codebuild_role_arn
  eventbridge_role_arn  = module.iam.eventbridge_role_arn

  ecs_cluster_name        = var.ecs_cluster_name
  ecs_service_name        = var.ecs_service_name
  codedeploy_app_name     = var.codedeploy_app_name
  codedeploy_group_name   = var.codedeploy_group_name
  task_execution_role_arn = var.task_execution_role_arn
}
