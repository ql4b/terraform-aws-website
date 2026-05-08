locals {
  fqdn = var.fqdn
}

data "aws_route53_zone" "default" {
  name = local.fqdn 
}

module "acm_certificate" {
  source  = "cloudposse/acm-request-certificate/aws"
  version = "0.18.0"  

  domain_name                       = local.fqdn
  subject_alternative_names         = []
  process_domain_validation_options = true
  ttl                               = "300"
}

module "cdn" {
  source  = "cloudposse/cloudfront-s3-cdn/aws"
  version = "0.96.0"
    
  context     = module.this.context
  attributes  = []

  acm_certificate_arn               = module.acm_certificate.arn
  viewer_protocol_policy            = "redirect-to-https"
  dns_alias_enabled                 = true
  parent_zone_name                  = data.aws_route53_zone.default.name
  cloudfront_access_logging_enabled = false

  default_root_object = var.default_root_object

  aliases = local.fqdn != null ? [local.fqdn] : []

  website_enabled = false
    
  depends_on = [module.acm_certificate]
}