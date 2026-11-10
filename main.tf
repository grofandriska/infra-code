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

  # The bucket you created by hand in step 0. Backends can't use variables, write the values here.
  backend "s3" {
    bucket       = "CHANGE-ME"
    key          = "infra-code/terraform.tfstate"
    region       = "CHANGE-ME"
    use_lockfile = true
  }
}

provider "aws" {
  region = "CHANGE-ME"
}
