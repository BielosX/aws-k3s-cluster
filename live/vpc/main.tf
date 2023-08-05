terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
      version = "5.11.0"
    }
  }
  backend "s3" {
    key = "vpc.tfstate"
  }
}

provider "aws" {
  region = "eu-west-1"
}

module "vpc" {
  source = "../../modules/vpc"
  availability-zones = ["eu-west-1a", "eu-west-1b", "eu-west-1c"]
  cidr-block = "10.0.0.0/16"
  single-nat-gateway = true
}