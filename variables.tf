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
