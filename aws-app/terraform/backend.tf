terraform {
  required_version = ">= 1.6"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
  }

  backend "s3" {
    # terraform init -backend-config="bucket=<YOUR_TFSTATE_BUCKET>" \
    #               -backend-config="key=aws-app/terraform.tfstate" \
    #               -backend-config="region=ap-northeast-1"
  }
}

provider "aws" {
  region = var.aws_region
}
