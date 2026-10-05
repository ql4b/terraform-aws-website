# Subdomain + API example — a site on a delegated subdomain zone created in the
# same configuration, with an API path routed to a Lambda Function URL and a
# custom 404 page for missing S3 objects.
#
# Requires an existing Route53 hosted zone for var.parent_zone_name; this
# example creates the var.fqdn zone and delegates it from the parent.

provider "aws" {
  region = "us-east-1"
}

variable "fqdn" {
  description = "FQDN of the website, a subdomain of parent_zone_name (e.g. app.example.com)"
  type        = string
}

variable "parent_zone_name" {
  description = "Existing parent Route53 hosted zone (e.g. example.com)"
  type        = string
}

variable "api_origin_domain" {
  description = "Domain of the API origin, e.g. a Lambda Function URL host (abc123.lambda-url.us-east-1.on.aws)"
  type        = string
}

# --- Delegated subdomain zone ---------------------------------------------

data "aws_route53_zone" "parent" {
  name = var.parent_zone_name
}

resource "aws_route53_zone" "site" {
  name = var.fqdn
}

resource "aws_route53_record" "delegation" {
  zone_id = data.aws_route53_zone.parent.zone_id
  name    = var.fqdn
  type    = "NS"
  ttl     = 300
  records = aws_route53_zone.site.name_servers
}

# --- Managed CloudFront policies for the API path -------------------------

data "aws_cloudfront_cache_policy" "disabled" {
  name = "Managed-CachingDisabled"
}

data "aws_cloudfront_origin_request_policy" "all_except_host" {
  name = "Managed-AllViewerExceptHostHeader"
}

# --- Website ----------------------------------------------------------------

module "website" {
  source = "../../"

  fqdn            = var.fqdn
  route53_zone_id = aws_route53_zone.site.zone_id

  custom_origins = [{
    domain_name          = var.api_origin_domain
    origin_id            = "api"
    custom_origin_config = {}
  }]

  ordered_cache = [{
    target_origin_id         = "api"
    path_pattern             = "/v1/*"
    allowed_methods          = ["GET", "HEAD", "OPTIONS"]
    cache_policy_id          = data.aws_cloudfront_cache_policy.disabled.id
    origin_request_policy_id = data.aws_cloudfront_origin_request_policy.all_except_host.id
  }]

  # Serve the site's 404 page for missing objects (S3 answers 404 NoSuchKey;
  # 403 covers bucket policies that hide missing keys).
  custom_error_response = [
    for code in ["403", "404"] : {
      error_code            = code
      response_code         = 404
      response_page_path    = "/404.html"
      error_caching_min_ttl = 10
    }
  ]

  context = {
    namespace = "myorg"
    name      = "website"
  }

  # Certificate validation records land in the new zone; it must be reachable
  # through the parent delegation before ACM can validate.
  depends_on = [aws_route53_record.delegation]
}

output "website_url" {
  value = module.website.website_url
}
