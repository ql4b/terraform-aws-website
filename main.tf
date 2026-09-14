locals {
  fqdn = var.fqdn

  basic_auth_enabled = try(var.basic_auth.enabled, false)

  # Basic Auth occupies the viewer-request event when enabled.
  basic_auth_association = local.basic_auth_enabled ? [{
    event_type   = "viewer-request"
    function_arn = aws_cloudfront_function.basic_auth[0].arn
  }] : []

  # Merge the module-managed Basic Auth association with consumer-supplied
  # functions. CloudFront permits only one function per event type, so a
  # consumer viewer-request function cannot coexist with Basic Auth (guarded
  # by the precondition on terraform_data.function_association_guard below).
  function_associations = concat(local.basic_auth_association, var.cloudfront_function_associations)

  # Does the consumer supply a viewer-request function? Used for the guard.
  consumer_has_viewer_request = length([
    for a in var.cloudfront_function_associations : a if a.event_type == "viewer-request"
  ]) > 0
}

# Fail fast (at plan) if Basic Auth and a consumer viewer-request function
# would both bind to viewer-request. CloudFront allows only one per event type.
resource "terraform_data" "function_association_guard" {
  lifecycle {
    precondition {
      condition     = !(local.basic_auth_enabled && local.consumer_has_viewer_request)
      error_message = "basic_auth is enabled and cloudfront_function_associations also contains a 'viewer-request' function. CloudFront allows only one function per event type. Disable basic_auth and fold the auth check into your own viewer-request function, or move your function to 'viewer-response'."
    }
  }
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

  # Attach the Basic Auth CloudFront Function (viewer-request, when enabled)
  # plus any consumer-supplied functions. See locals above.
  function_association = local.function_associations

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

  # S3 delivery options only apply when the consumer supplied an S3 bucket ARN
  # as the destination. Gate on the *input* (var.standard_logging_v2.destination_arn),
  # which is known at plan time -- not on local.slv2_destination_arn, which is
  # the created log group ARN (unknown until apply) when the module makes the
  # log group. A module-created destination is always CloudWatch Logs, never S3.
  slv2_is_s3_destination = local.slv2_enabled && (
    var.standard_logging_v2.destination_arn != null &&
    can(regex("^arn:aws[a-z-]*:s3:", var.standard_logging_v2.destination_arn))
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


# ---------------------------------------------------------------------------
# Basic Auth (CloudFront Function, viewer-request)
#
# Gates the distribution behind HTTP Basic Auth to keep non-production sites
# non-public. This is a coarse gate, NOT real authentication: the expected
# credential is embedded (base64) in the function source and therefore visible
# in the CloudFront console and in Terraform state. Do not use it to protect
# sensitive data.
#
# The function runs on viewer-request and compares the Authorization header
# against the expected "Basic <base64(user:pass)>" value, returning 401 with a
# WWW-Authenticate challenge on mismatch. The code targets the cloudfront-js-2.0
# runtime (ECMAScript 5.1-compatible; no template literals).
# ---------------------------------------------------------------------------

locals {
  basic_auth_expected = local.basic_auth_enabled ? format(
    "Basic %s",
    base64encode(format("%s:%s", var.basic_auth.username, var.basic_auth.password))
  ) : ""

  basic_auth_code = <<-EOT
    function handler(event) {
      var request = event.request;
      var headers = request.headers;
      var expected = "${local.basic_auth_expected}";

      if (headers.authorization && headers.authorization.value === expected) {
        return request;
      }

      return {
        statusCode: 401,
        statusDescription: 'Unauthorized',
        headers: {
          'www-authenticate': { value: 'Basic realm="Restricted"' }
        }
      };
    }
  EOT
}

resource "aws_cloudfront_function" "basic_auth" {
  count = local.basic_auth_enabled ? 1 : 0

  name    = "${module.this.id}-basic-auth"
  runtime = "cloudfront-js-2.0"
  comment = "Basic Auth gate for ${local.fqdn}"
  publish = true
  code    = local.basic_auth_code
}
