# CloudFront outputs
output "cf_id" {
  description = "CloudFront distribution ID"
  value       = module.cdn.cf_id
}

output "cf_arn" {
  description = "CloudFront distribution ARN"
  value       = module.cdn.cf_arn
}

output "cf_domain_name" {
  description = "CloudFront distribution domain name"
  value       = module.cdn.cf_domain_name
}

output "cf_hosted_zone_id" {
  description = "CloudFront distribution hosted zone ID"
  value       = module.cdn.cf_hosted_zone_id
}

output "cf_origin_access_identity_iam_arn" {
  description = "CloudFront Origin Access Identity IAM ARN"
  value       = module.cdn.cf_origin_access_identity_iam_arn
}

# S3 outputs
output "s3_bucket" {
  description = "S3 bucket name"
  value       = module.cdn.s3_bucket
}

output "s3_bucket_arn" {
  description = "S3 bucket ARN"
  value       = module.cdn.s3_bucket_arn
}

output "s3_bucket_domain_name" {
  description = "S3 bucket domain name"
  value       = module.cdn.s3_bucket_domain_name
}

output "s3_bucket_hosted_zone_id" {
  description = "S3 bucket hosted zone ID"
  value       = module.cdn.s3_bucket_hosted_zone_id
}

# Route53 outputs
output "route53_zone_id" {
  description = "Route53 hosted zone ID"
  value       = data.aws_route53_zone.default.zone_id
}

output "route53_zone_name" {
  description = "Route53 hosted zone name"
  value       = data.aws_route53_zone.default.name
}

output "route53_name_servers" {
  description = "Route53 hosted zone name servers"
  value       = data.aws_route53_zone.default.name_servers
}

# ACM Certificate outputs
output "acm_certificate_arn" {
  description = "ACM certificate ARN"
  value       = module.acm_certificate.arn
}

output "acm_certificate_domain_validation_options" {
  description = "ACM certificate domain validation options"
  value       = module.acm_certificate.domain_validation_options
}

output "acm_certificate_status" {
  description = "ACM certificate status"
  value       = module.acm_certificate.status
}

# Convenience outputs
output "website_url" {
  description = "Website URL"
  value       = "https://${var.fqdn}"
}

output "fqdn" {
  description = "Fully qualified domain name"
  value       = var.fqdn
}