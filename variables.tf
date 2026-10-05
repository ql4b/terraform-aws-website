variable "fqdn" {
  type        = string
  description = "FQDN of the website"
}

variable "default_root_object" {
  type        = string
  description = "Default root object for CloudFront"
  default     = "index.html"
}

variable "basic_auth" {
  type = object({
    enabled  = optional(bool, false)
    username = optional(string, null)
    password = optional(string, null)
  })
  description = "Gate the distribution behind HTTP Basic Auth via a CloudFront Function on viewer-request. Intended to keep non-production sites non-public; not a substitute for real authentication (the credential is embedded in the function source and Terraform state)."
  default     = {}
  sensitive   = true

  validation {
    condition     = !try(var.basic_auth.enabled, false) || (try(var.basic_auth.username, null) != null && try(var.basic_auth.password, null) != null)
    error_message = "When basic_auth.enabled is true, both basic_auth.username and basic_auth.password must be set."
  }
}

variable "cloudfront_function_associations" {
  type = list(object({
    event_type   = string
    function_arn = string
  }))
  description = "Consumer-supplied CloudFront Functions to attach to the default cache behavior (e.g. redirects, header rewrites). The consumer owns the aws_cloudfront_function resource and passes its ARN. event_type is 'viewer-request' or 'viewer-response'. Note: CloudFront allows only one function per event type; a 'viewer-request' entry here conflicts with basic_auth (fold auth into your own function instead)."
  default     = []

  validation {
    condition     = alltrue([for a in var.cloudfront_function_associations : contains(["viewer-request", "viewer-response"], a.event_type)])
    error_message = "Each cloudfront_function_associations event_type must be 'viewer-request' or 'viewer-response'."
  }
}

variable "standard_logging_v2_enabled" {
  type        = bool
  description = "Enable CloudFront standard logging (v2) via CloudWatch Logs vended log delivery. Independent of the CloudPosse module's legacy access logging."
  default     = false
}

variable "standard_logging_v2" {
  type = object({
    # Destination. Leave destination_arn null to have the module create a
    # CloudWatch Logs log group. Set it to an existing CloudWatch Logs log
    # group, S3 bucket, or Firehose delivery stream ARN to deliver there
    # instead (the module then creates no log group).
    destination_arn = optional(string, null)

    # Only used when the module creates the log group (destination_arn == null).
    log_group_name        = optional(string, null)
    log_group_retention   = optional(number, 90)
    log_group_kms_key_arn = optional(string, null)

    # Output format of delivered logs. One of: json, plain, w3c, raw, parquet.
    output_format = optional(string, "json")

    # Ordered list of access-log record fields to deliver. Leave null to use
    # the AWS default field set.
    record_fields = optional(list(string), null)

    # S3-only delivery options (ignored for CloudWatch Logs / Firehose).
    s3_suffix_path                 = optional(string, null)
    s3_enable_hive_compatible_path = optional(bool, null)
  })
  description = "Configuration for CloudFront standard logging (v2). Only used when standard_logging_v2_enabled is true; sensible defaults make the zero-config case create a CloudWatch Logs log group."
  default     = {}
}

variable "route53_zone_id" {
  type        = string
  description = "ID of the Route53 hosted zone that holds `fqdn`. When null (default), the zone is looked up by name and must be named exactly `fqdn`. Set it to use a zone created in the same configuration (e.g. a delegated subdomain zone) or any zone whose name differs from `fqdn`."
  default     = null
}

variable "custom_origins" {
  type = list(object({
    domain_name                 = string
    origin_id                   = string
    origin_path                 = optional(string, "")
    origin_access_control_id    = optional(string, null)
    response_completion_timeout = optional(number, 0)
    custom_headers = optional(list(object({
      name  = string
      value = string
    })), [])
    custom_origin_config = object({
      http_port                = optional(number, 80)
      https_port               = optional(number, 443)
      origin_protocol_policy   = optional(string, "https-only")
      origin_ssl_protocols     = optional(list(string), ["TLSv1.2"])
      origin_keepalive_timeout = optional(number, 5)
      origin_read_timeout      = optional(number, 30)
    })
    origin_shield = optional(object({
      enabled = optional(bool, false)
      region  = optional(string, null)
    }), null)
  }))
  description = "Additional custom (non-S3) origins, e.g. a Lambda Function URL or an API host. Passed through to cloudposse/cloudfront-s3-cdn. Route paths to them with `ordered_cache`."
  default     = []
}

variable "ordered_cache" {
  type = list(object({
    target_origin_id = string
    path_pattern     = string

    allowed_methods    = optional(list(string), ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"])
    cached_methods     = optional(list(string), ["GET", "HEAD"])
    compress           = optional(bool, false)
    trusted_signers    = optional(list(string), [])
    trusted_key_groups = optional(list(string), [])

    cache_policy_id          = optional(string, null)
    origin_request_policy_id = optional(string, null)
    realtime_log_config_arn  = optional(string, null)

    viewer_protocol_policy     = optional(string, "redirect-to-https")
    min_ttl                    = optional(number, 0)
    default_ttl                = optional(number, 60)
    max_ttl                    = optional(number, 31536000)
    response_headers_policy_id = optional(string, "")

    grpc_config = optional(object({
      enabled = bool
    }), { enabled = false })

    forward_query_string              = optional(bool, false)
    forward_header_values             = optional(list(string), [])
    forward_cookies                   = optional(string, "none")
    forward_cookies_whitelisted_names = optional(list(string), [])

    lambda_function_association = optional(list(object({
      event_type   = string
      include_body = optional(bool, false)
      lambda_arn   = string
    })), [])

    function_association = optional(list(object({
      event_type   = string
      function_arn = string
    })), [])
  }))
  description = "Ordered cache behaviors, evaluated before the default (S3) behavior, in list order. `target_origin_id` must match a `custom_origins` entry's `origin_id`. Passed through to cloudposse/cloudfront-s3-cdn. Prefer `cache_policy_id` / `origin_request_policy_id` over the legacy `forward_*` fields."
  default     = []
}

variable "custom_error_response" {
  type = list(object({
    error_caching_min_ttl = optional(number, null)
    error_code            = string
    response_code         = optional(number, null)
    response_page_path    = optional(string, null)
  }))
  description = "Custom error responses for the distribution, e.g. map the 403 an S3 origin returns for a missing object to a 404 page. Passed through to cloudposse/cloudfront-s3-cdn."
  default     = []
}
