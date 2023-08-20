terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
      version = "5.11.0"
    }
  }
  backend "s3" {
    key = "control-plane.tfstate"
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

module "control-plane" {
  source = "../../modules/control-plane"
  subnet-ids = data.terraform_remote_state.vpc.outputs.private-subnet-ids
  vpc-id = data.terraform_remote_state.vpc.outputs.vpc-id
  ami = "ami-0bd2107e291d3cac5"
  kubernetes-pod-cidr = "172.16.0.0/16"
  kubernetes-service-cidr = "172.17.0.0/16"
  kubernetes-cluster-dns = "172.17.0.10"
  node-manager-image = var.node-manager-image
}