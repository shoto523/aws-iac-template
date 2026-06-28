# ----------------------------------------
# CloudWatch Logs（CodeBuildビルドログ）
# ----------------------------------------
resource "aws_cloudwatch_log_group" "codebuild" {
  name              = "/codebuild/${var.project_name}"
  retention_in_days = 30

  tags = { Project = var.project_name }
}

# ----------------------------------------
# CodeBuild
# ----------------------------------------
resource "aws_codebuild_project" "main" {
  name         = "${var.project_name}-build"
  service_role = var.codebuild_role_arn

  source {
    type      = "CODEPIPELINE"
    buildspec = "buildspec.yml"
  }

  artifacts {
    type = "CODEPIPELINE"
  }

  environment {
    compute_type                = "BUILD_GENERAL1_SMALL"
    image                       = "aws/codebuild/standard:7.0"
    type                        = "LINUX_CONTAINER"
    image_pull_credentials_type = "CODEBUILD"
    privileged_mode             = true

    environment_variable {
      name  = "ECR_REPOSITORY_URI"
      value = var.ecr_repository_url
    }

    environment_variable {
      name  = "AWS_DEFAULT_REGION"
      value = var.aws_region
    }

    environment_variable {
      name  = "CONTAINER_NAME"
      value = var.project_name
    }
  }

  logs_config {
    cloudwatch_logs {
      group_name  = aws_cloudwatch_log_group.codebuild.name
      stream_name = "build"
    }
  }

  tags = { Project = var.project_name }
}

# ----------------------------------------
# CodePipeline
# ----------------------------------------
resource "aws_codepipeline" "main" {
  name     = "${var.project_name}-pipeline"
  role_arn = var.codepipeline_role_arn

  artifact_store {
    location = var.artifact_bucket_name
    type     = "S3"
  }

  stage {
    name = "Source"

    dynamic "action" {
      for_each = var.source_type == "codecommit" ? [1] : []
      content {
        name             = "Source"
        category         = "Source"
        owner            = "AWS"
        provider         = "CodeCommit"
        version          = "1"
        output_artifacts = ["source_output"]
        configuration = {
          RepositoryName       = var.codecommit_repo_name
          BranchName           = var.codecommit_branch
          OutputArtifactFormat = "CODE_ZIP"
          PollForSourceChanges = "false"
        }
      }
    }

    dynamic "action" {
      for_each = var.source_type == "github" ? [1] : []
      content {
        name             = "Source"
        category         = "Source"
        owner            = "AWS"
        provider         = "CodeStarSourceConnection"
        version          = "1"
        output_artifacts = ["source_output"]
        configuration = {
          ConnectionArn        = var.connection_arn
          FullRepositoryId     = "${var.github_owner}/${var.github_repo}"
          BranchName           = var.github_branch
          OutputArtifactFormat = "CODE_ZIP"
        }
      }
    }
  }

  stage {
    name = "Build"

    action {
      name             = "Build"
      category         = "Build"
      owner            = "AWS"
      provider         = "CodeBuild"
      version          = "1"
      input_artifacts  = ["source_output"]
      output_artifacts = ["build_output"]
      configuration = {
        ProjectName = aws_codebuild_project.main.name
      }
    }
  }

  stage {
    name = "Deploy"

    action {
      name            = "Deploy"
      category        = "Deploy"
      owner           = "AWS"
      provider        = "CodeDeployToECS"
      version         = "1"
      input_artifacts = ["build_output"]
      configuration = {
        ApplicationName                = var.codedeploy_app_name
        DeploymentGroupName            = var.codedeploy_group_name
        TaskDefinitionTemplateArtifact = "build_output"
        TaskDefinitionTemplatePath     = "taskdef.json"
        AppSpecTemplateArtifact        = "build_output"
        AppSpecTemplatePath            = "appspec.yaml"
        Image1ArtifactName             = "build_output"
        Image1ContainerName            = "IMAGE1_NAME"
      }
    }
  }

  tags = { Project = var.project_name }
}

# ----------------------------------------
# EventBridge（CodeCommit版のみ）
# ----------------------------------------
resource "aws_cloudwatch_event_rule" "codecommit_push" {
  count       = var.source_type == "codecommit" ? 1 : 0
  name        = "${var.project_name}-codecommit-push"
  description = "CodeCommit push → CodePipeline trigger"

  event_pattern = jsonencode({
    source      = ["aws.codecommit"]
    detail-type = ["CodeCommit Repository State Change"]
    resources   = [var.codecommit_repo_arn]
    detail = {
      event         = ["referenceCreated", "referenceUpdated"]
      referenceType = ["branch"]
      referenceName = [var.codecommit_branch]
    }
  })

  tags = { Project = var.project_name }
}

resource "aws_cloudwatch_event_target" "pipeline" {
  count     = var.source_type == "codecommit" ? 1 : 0
  rule      = aws_cloudwatch_event_rule.codecommit_push[0].name
  target_id = "CodePipeline"
  arn       = aws_codepipeline.main.arn
  role_arn  = var.eventbridge_role_arn
}
