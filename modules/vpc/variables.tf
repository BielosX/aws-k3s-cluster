variable "availability-zones" {
  type = list(string)
}

variable "cidr-block" {
  type = string
}

variable "single-nat-gateway" {
  type = bool
}