variable "ami" {
  type = string
}

variable "init-script" {
  type = string
}

variable "cloud-watch-config" {
  type = map(string)
}

variable "min-size" {
  type = number
}

variable "max-size" {
  type = number
}

variable "instance-type" {
  type = string
}

variable "security-group-ids" {
  type = list(string)
}

variable "subnet-ids" {
  type = list(string)
}

variable "instance-managed-policies" {
  type = list(string)
}

variable "instance-policy" {
  type = string
  default = ""
}