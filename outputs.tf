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
  value       = module.cdn.cf_identity_iam_arn
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

# Convenience outputs
output "website_url" {
  description = "Website URL"
  value       = "https://${var.fqdn}"
}

output "fqdn" {
  description = "Fully qualified domain name"
  value       = var.fqdn
}

# CloudFront standard logging (v2) outputs
output "cf_log_group_name" {
  description = "Name of the CloudWatch Logs log group created for CloudFront standard logging (v2). Null when logging is disabled or an external destination is used."
  value       = one(aws_cloudwatch_log_group.cf_access_logs[*].name)
}

output "cf_log_group_arn" {
  description = "ARN of the CloudWatch Logs log group created for CloudFront standard logging (v2). Null when logging is disabled or an external destination is used."
  value       = one(aws_cloudwatch_log_group.cf_access_logs[*].arn)
}

output "cf_log_delivery_destination_arn" {
  description = "ARN of the CloudWatch Logs delivery destination for CloudFront standard logging (v2). Null when logging is disabled."
  value       = one(aws_cloudwatch_log_delivery_destination.cf_access_logs[*].arn)
}

output "cf_log_delivery_id" {
  description = "ID of the CloudWatch Logs delivery for CloudFront standard logging (v2). Null when logging is disabled."
  value       = one(aws_cloudwatch_log_delivery.cf_access_logs[*].id)
}

# Basic Auth outputs
output "basic_auth_function_arn" {
  description = "ARN of the Basic Auth CloudFront Function. Null when basic_auth is disabled."
  value       = one(aws_cloudfront_function.basic_auth[*].arn)
}

output "basic_auth_enabled" {
  description = "Whether Basic Auth gating is enabled on the distribution."
  value       = local.basic_auth_enabled
}
