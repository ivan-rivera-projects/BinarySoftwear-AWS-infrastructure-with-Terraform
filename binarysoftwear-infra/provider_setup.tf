terraform {
  required_version = ">= 1.2.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

# Provider specifically for CloudFront and global resources (must be in us-east-1)
provider "aws" {
  alias  = "us-east-1"
  region = "us-east-1"
}
