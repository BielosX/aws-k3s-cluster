terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
      version = "5.11.0"
    }
  }
  backend "s3" {
    key = "bastion.tfstate"
  }
}

provider "aws" {
  region = "eu-west-1"
}

data "terraform_remote_state" "vpc" {
  backend = "s3"
  config = {
    key = "vpc.tfstate"
    dynamodb_table = "terraform-state-lock"
    bucket = var.vpc-state-bucket
  }
}

module "bastion" {
  source = "../../modules/bastion"
  public-subnet-id = data.terraform_remote_state.vpc.outputs.public-subnet-ids[0]
  vpc-id = data.terraform_remote_state.vpc.outputs.vpc-id
}