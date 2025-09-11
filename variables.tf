variable "fqdn" {
  type        = string
  description = "FQDN of the website"
}

variable "default_root_object" {
  type        = string
  description = "Default root object for CloudFront"
  default     = "index.html"
}

