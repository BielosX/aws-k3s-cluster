variable "lambda-file-path" {
  type = string
}

variable "subnets" {
  type = list(string)
}

variable "security-group-id" {
  type = string
}