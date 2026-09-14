variable "fqdn" {
  type        = string
  description = "FQDN of the website"
}

variable "default_root_object" {
  type        = string
  description = "Default root object for CloudFront"
  default     = "index.html"
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
