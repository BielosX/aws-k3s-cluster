variable "vpc-id" {
  type = string
}

variable "subnet-ids" {
  type = list(string)
}

variable "ami" {
  type = string
}

variable "kubernetes-node-sg-id" {
  type = string
}