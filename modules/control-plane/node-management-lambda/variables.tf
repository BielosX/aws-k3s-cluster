variable "control-plane-service-id" {
  type = string
}

variable "subnet-ids" {
  type = list(string)
}

variable "vpc-id" {
  type = string
}

variable "security-group-id" {
  type = string
}

variable "file-path" {
  type = string
}