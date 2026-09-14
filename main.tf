locals {
  fqdn = var.fqdn
}

data "aws_route53_zone" "default" {
  name = local.fqdn
}

module "acm_certificate" {
  source  = "cloudposse/acm-request-certificate/aws"
  version = "0.18.1"

  domain_name                       = local.fqdn
  subject_alternative_names         = []
  process_domain_validation_options = true
  ttl                               = "300"
}

module "cdn" {
  source  = "cloudposse/cloudfront-s3-cdn/aws"
  version = "2.1.1"

  context    = module.this.context
  attributes = []

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


# ---------------------------------------------------------------------------
# CloudFront standard logging (v2)
#
# Delivers CloudFront access logs through the CloudWatch Logs vended-log
# delivery pipeline (source -> destination -> delivery), wired to the
# distribution created by the CloudPosse module. This is independent of that
# module's legacy access logging (cloudfront_access_logging_enabled).
#
# When standard_logging_v2.destination_arn is null, the module creates a
# CloudWatch Logs log group and delivers there. Otherwise it delivers to the
# supplied ARN (an existing log group, S3 bucket, or Firehose stream) and
# creates no log group.
# ---------------------------------------------------------------------------

locals {
  slv2_enabled = var.standard_logging_v2_enabled

  # Create a CWL log group only when enabled and no external destination given.
  slv2_create_log_group = local.slv2_enabled && var.standard_logging_v2.destination_arn == null

  slv2_log_group_name = coalesce(
    var.standard_logging_v2.log_group_name,
    "/aws/cloudfront/${module.this.id}"
  )

  # Resolve the destination ARN: external if provided, else the created group.
  slv2_destination_arn = local.slv2_enabled ? (
    local.slv2_create_log_group
    ? aws_cloudwatch_log_group.cf_access_logs[0].arn
    : var.standard_logging_v2.destination_arn
  ) : null

  # S3 delivery options only apply when the destination is an S3 bucket.
  slv2_is_s3_destination = local.slv2_enabled && (
    local.slv2_destination_arn != null &&
    can(regex("^arn:aws[a-z-]*:s3:", local.slv2_destination_arn))
  )
}

resource "aws_cloudwatch_log_group" "cf_access_logs" {
  count = local.slv2_create_log_group ? 1 : 0

  name              = local.slv2_log_group_name
  retention_in_days = var.standard_logging_v2.log_group_retention
  kms_key_id        = var.standard_logging_v2.log_group_kms_key_arn

  tags = module.this.tags
}

resource "aws_cloudwatch_log_delivery_source" "cf_access_logs" {
  count = local.slv2_enabled ? 1 : 0

  name         = "${module.this.id}-cf-access-logs"
  log_type     = "ACCESS_LOGS"
  resource_arn = module.cdn.cf_arn

  tags = module.this.tags
}

resource "aws_cloudwatch_log_delivery_destination" "cf_access_logs" {
  count = local.slv2_enabled ? 1 : 0

  name          = "${module.this.id}-cf-access-logs"
  output_format = var.standard_logging_v2.output_format

  delivery_destination_configuration {
    destination_resource_arn = local.slv2_destination_arn
  }

  tags = module.this.tags
}

resource "aws_cloudwatch_log_delivery" "cf_access_logs" {
  count = local.slv2_enabled ? 1 : 0

  delivery_source_name     = aws_cloudwatch_log_delivery_source.cf_access_logs[0].name
  delivery_destination_arn = aws_cloudwatch_log_delivery_destination.cf_access_logs[0].arn

  record_fields = var.standard_logging_v2.record_fields

  dynamic "s3_delivery_configuration" {
    for_each = local.slv2_is_s3_destination ? ["true"] : []

    content {
      suffix_path                 = var.standard_logging_v2.s3_suffix_path
      enable_hive_compatible_path = var.standard_logging_v2.s3_enable_hive_compatible_path
    }
  }

  tags = module.this.tags
}
