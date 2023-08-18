variable "ami" {
  type = string
}

variable "init-script" {
  type = string
}

variable "cloud-watch-config" {
  type = map(any)
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

variable "target-group-arns" {
  type = list(string)
  default = []
}

variable "instance-name" {
  type = string
  default = ""
}

variable "instance-metadata-tags" {
  type = bool
  default = true
}

variable "metadata-http-endpoint" {
  type = bool
  default = true
}

variable "metadata-http-tokens" {
  type = string
  default = "required"
  validation {
    condition = contains(["required", "optional"], var.metadata-http-tokens)
    error_message = "metadata-http-tokens should be either 'required' or 'optional'"
  }
}

variable "metadata-hop-limit" {
  type = number
  default = 1
}

variable "write-files" {
  type = list(object({
    destination = string
    permissions = string
    contentFile = string
  }))
  default = []
}