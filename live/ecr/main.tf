terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
      version = "5.11.0"
    }
  }
  backend "s3" {
    key = "ecr.tfstate"
  }
}

provider "aws" {
  region = "eu-west-1"
}

module "ecr" {
  source = "../../modules/ecr"
}