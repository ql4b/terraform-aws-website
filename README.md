# terraform-aws-website

> Complete website infrastructure from just a domain name

Terraform module that creates a production-ready website with CloudFront CDN, S3 hosting, SSL certificate, and Route53 DNS configuration.

## Features

- **CloudFront CDN** with S3 origin
- **SSL Certificate** via ACM with automatic validation
- **Route53 DNS** alias configuration
- **HTTPS redirect** enforced
- **Standard logging (v2)** opt-in — CloudFront access logs via CloudWatch Logs vended log delivery
- **Minimal configuration** - just provide FQDN

## Usage

```hcl
module "website" {
  source = "git::https://github.com/ql4b/terraform-aws-website.git?ref=v1.0.0"
  
  fqdn = "example.com"
  
  context = {
    namespace = "myorg"
    name      = "website"
  }
}
```

## Requirements

- Route53 hosted zone for the domain must exist
- AWS provider with appropriate permissions

## CloudFront Standard Logging (v2)

Standard logging (v2) delivers CloudFront access logs through the CloudWatch
Logs vended log delivery pipeline. It is **disabled by default** and is
independent of the underlying CloudPosse module's legacy access logging.

Enable it with a single flag. The zero-config case creates a CloudWatch Logs
log group and delivers logs there:

```hcl
module "website" {
  source = "git::https://github.com/ql4b/terraform-aws-website.git?ref=v1.0.0"

  fqdn = "example.com"

  standard_logging_v2_enabled = true

  context = {
    namespace = "myorg"
    name      = "website"
  }
}
```

Deliver to an existing destination (CloudWatch Logs log group, S3 bucket, or
Firehose delivery stream) instead of creating a log group — pass its ARN. When
`destination_arn` is set, the module creates no log group:

```hcl
module "website" {
  source = "git::https://github.com/ql4b/terraform-aws-website.git?ref=v1.0.0"

  fqdn = "example.com"

  standard_logging_v2_enabled = true
  standard_logging_v2 = {
    destination_arn = aws_s3_bucket.logs.arn
    output_format   = "parquet"
    s3_suffix_path  = "cloudfront/{yyyy}/{MM}/{dd}"

    # Leave record_fields unset to use the AWS default field set.
    record_fields = ["date", "time", "c-ip", "sc-status", "cs-uri-stem"]
  }

  context = {
    namespace = "myorg"
    name      = "website"
  }
}
```

### `standard_logging_v2` options

| Field | Default | Description |
|-------|---------|-------------|
| `destination_arn` | `null` | Existing CloudWatch Logs log group, S3 bucket, or Firehose ARN. `null` means the module creates a CloudWatch Logs log group. |
| `log_group_name` | `/aws/cloudfront/<id>` | Name of the log group when the module creates it. |
| `log_group_retention` | `90` | Log group retention in days (when created by the module). |
| `log_group_kms_key_arn` | `null` | KMS key ARN for log group encryption (when created by the module). |
| `output_format` | `"json"` | Delivered log format: `json`, `plain`, `w3c`, `raw`, or `parquet`. |
| `record_fields` | `null` (AWS default) | Ordered list of access-log fields to deliver. |
| `s3_suffix_path` | `null` | S3 object prefix (S3 destinations only; AWS prepends its own managed prefix). |
| `s3_enable_hive_compatible_path` | `null` | Use a Hive-compatible S3 prefix structure (S3 destinations only). |

## Outputs

- `s3_bucket` - S3 bucket name for content
- `cf_id` - CloudFront distribution ID
- `website_url` - Complete website URL

Standard logging (v2) outputs (null when logging is disabled):

- `cf_log_group_name` - Name of the created CloudWatch Logs log group
- `cf_log_group_arn` - ARN of the created CloudWatch Logs log group
- `cf_log_delivery_destination_arn` - ARN of the log delivery destination
- `cf_log_delivery_id` - ID of the log delivery

## Deploy Content

```bash
aws s3 sync ./dist s3://$(terraform output -raw s3_bucket)
aws cloudfront create-invalidation --distribution-id $(terraform output -raw cf_id) --paths '/*'
```