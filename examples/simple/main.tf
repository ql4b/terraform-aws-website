# Simple example — a public website with all defaults.
# Requires an existing Route53 hosted zone whose name equals var.fqdn.

provider "aws" {
  region = "us-east-1"
}

variable "fqdn" {
  description = "FQDN of the website (a Route53 hosted zone with this name must exist)"
  type        = string
}

module "website" {
  source = "../../"

  fqdn = var.fqdn

  context = {
    namespace = "myorg"
    name      = "website"
  }
}

output "s3_bucket" {
  description = "Origin S3 bucket — sync your content here"
  value       = module.website.s3_bucket
}

output "cf_id" {
  description = "CloudFront distribution ID — use for invalidations"
  value       = module.website.cf_id
}

output "website_url" {
  value = module.website.website_url
}
