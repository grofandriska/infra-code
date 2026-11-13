provider "aws" {
  region = var.region
}

terraform {
  required_version = ">= 1.10"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 3.0"
    }
  }

  backend "s3" {
    bucket       = "andras-csk-w10-tfstate"
    key          = "infra-code/terraform.tfstate"
    region       = var.region
    use_lockfile = true
  }
}




