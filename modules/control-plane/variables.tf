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

variable "management-lambda-file-path" {
  type = string
}