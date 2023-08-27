variable "vpc-id" {
  type = string
}

variable "subnet-ids" {
  type = list(string)
}

variable "ami" {
  type = string
}

variable "kubernetes-pod-cidr" {
  type = string
  default = "10.42.0.0/16"
}

variable "kubernetes-service-cidr" {
  type = string
  default = "10.43.0.0/16"
}

variable "kubernetes-cluster-dns" {
  type = string
  default = "10.43.0.10"
}

variable "node-manager-image" {
  type = string
}

variable "iam-role-provider-lambda-jar" {
  type = string
}