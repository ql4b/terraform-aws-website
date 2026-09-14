# Logging example — CloudFront standard logging (v2) to an S3 bucket the
# consumer owns, with partitioned, Hive-compatible paths.
# Requires an existing Route53 hosted zone whose name equals var.fqdn.

provider "aws" {
  region = "us-east-1"
}

variable "fqdn" {
  description = "FQDN of the website (a Route53 hosted zone with this name must exist)"
  type        = string
}

variable "log_bucket_arn" {
  description = "ARN of an existing S3 bucket to receive CloudFront access logs"
  type        = string
}

module "website" {
  source = "../../"

  fqdn = var.fqdn

  standard_logging_v2_enabled = true
  standard_logging_v2 = {
    destination_arn                = var.log_bucket_arn
    output_format                  = "parquet"
    s3_enable_hive_compatible_path = true
    s3_suffix_path                 = "{account-id}/{yyyy}/{MM}/{dd}/{HH}"
  }

  context = {
    namespace = "myorg"
    name      = "website"
  }
}

output "cf_log_delivery_id" {
  value = module.website.cf_log_delivery_id
}
