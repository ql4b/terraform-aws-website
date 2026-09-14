# Basic Auth example — gate a non-production site behind HTTP Basic Auth.
# Requires an existing Route53 hosted zone whose name equals var.fqdn.

provider "aws" {
  region = "us-east-1"
}

variable "fqdn" {
  description = "FQDN of the website (a Route53 hosted zone with this name must exist)"
  type        = string
}

variable "auth_username" {
  description = "Basic Auth username"
  type        = string
  sensitive   = true
}

variable "auth_password" {
  description = "Basic Auth password"
  type        = string
  sensitive   = true
}

module "website" {
  source = "../../"

  fqdn = var.fqdn

  basic_auth = {
    enabled  = true
    username = var.auth_username
    password = var.auth_password
  }

  context = {
    namespace = "myorg"
    name      = "website-qa"
  }
}

output "website_url" {
  value = module.website.website_url
}

output "basic_auth_function_arn" {
  value = module.website.basic_auth_function_arn
}
