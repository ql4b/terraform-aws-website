# terraform-aws-website

> Complete website infrastructure from just a domain name

Terraform module that creates a production-ready website with CloudFront CDN, S3 hosting, SSL certificate, and Route53 DNS configuration.

## Features

- **CloudFront CDN** with S3 origin
- **SSL Certificate** via ACM with automatic validation
- **Route53 DNS** alias configuration
- **HTTPS redirect** enforced
- **Basic Auth** opt-in — gate non-production sites behind a CloudFront Function
- **Custom CloudFront Functions** — attach your own redirect/rewrite functions
- **Standard logging (v2)** opt-in — CloudFront access logs via CloudWatch Logs vended log delivery
- **Minimal configuration** - just provide FQDN

## Usage

```hcl
module "website" {
  source = "git::https://github.com/ql4b/terraform-aws-website.git?ref=v2.0.0"
  
  fqdn = "example.com"
  
  context = {
    namespace = "myorg"
    name      = "website"
  }
}
```

## Requirements

- Terraform `>= 1.4` (uses `terraform_data`)
- AWS provider `>= 6.13.0` (required by `cloudfront-s3-cdn` 2.1.1)
- Route53 hosted zone for the domain must exist
- AWS credentials with appropriate permissions

## Basic Auth (keep a site non-public)

To keep a non-production site (e.g. a QA/staging environment) from being
publicly accessible, enable HTTP Basic Auth. This attaches a CloudFront
Function on `viewer-request` that challenges every request and returns `401`
unless the correct credentials are supplied.

```hcl
module "website" {
  source = "git::https://github.com/ql4b/terraform-aws-website.git?ref=v2.0.0"

  fqdn = "qa.example.com"

  basic_auth = {
    enabled  = true
    username = "qa"
    password = var.qa_password # keep this out of source; pass via a TF_VAR_ or tfvars
  }

  context = {
    namespace = "myorg"
    name      = "website"
  }
}
```

**This is a coarse gate, not real authentication.** The expected credential is
base64-encoded into the CloudFront Function source, so it is visible in the
CloudFront console and stored in Terraform state. Use it to keep casual
visitors and crawlers out of a dev/QA site — not to protect sensitive data. For
real auth, use Lambda@Edge with a proper identity provider.

Disabled by default. When enabled, both `username` and `password` are required.

## Custom CloudFront Functions (redirects, rewrites)

To attach your own edge logic — redirects, header rewrites, request
normalization — create the `aws_cloudfront_function` yourself and pass its ARN
via `cloudfront_function_associations`. The module does not author the function
code; you own it and its lifecycle.

```hcl
resource "aws_cloudfront_function" "redirects" {
  name    = "myorg-website-redirects"
  runtime = "cloudfront-js-2.0"
  publish = true
  code    = file("${path.module}/functions/redirects.js")
}

module "website" {
  source = "git::https://github.com/ql4b/terraform-aws-website.git?ref=v2.0.0"

  fqdn = "example.com"

  cloudfront_function_associations = [
    {
      event_type   = "viewer-request"
      function_arn = aws_cloudfront_function.redirects.arn
    },
  ]

  context = {
    namespace = "myorg"
    name      = "website"
  }
}
```

`event_type` must be `viewer-request` or `viewer-response`.

**One function per event type.** CloudFront allows only a single function per
event type on the default cache behavior. Because `basic_auth` occupies
`viewer-request`, you **cannot** enable `basic_auth` and also pass a
`viewer-request` function — the module fails at plan time with a clear message.
If you need both auth and redirects on viewer-request, fold the auth check into
your own function instead of using `basic_auth`, or move your function to
`viewer-response`.

## CloudFront Standard Logging (v2)

Standard logging (v2) delivers CloudFront access logs through the CloudWatch
Logs vended log delivery pipeline. It is **disabled by default** and is
independent of the underlying CloudPosse module's legacy access logging.

Enable it with a single flag. The zero-config case creates a CloudWatch Logs
log group and delivers logs there:

```hcl
module "website" {
  source = "git::https://github.com/ql4b/terraform-aws-website.git?ref=v2.0.0"

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
  source = "git::https://github.com/ql4b/terraform-aws-website.git?ref=v2.0.0"

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

### Delivering to an S3 bucket in a separate environment or account

The module deliberately does **not** create the S3 log bucket. You pass an
existing bucket ARN via `destination_arn`, so the bucket can live wherever you
want — a different Terraform stack/state, or a different AWS account (e.g. a
central logging account) — on its own lifecycle, owned by a different team.

**Partitioning still works regardless of where the bucket lives** — the
`s3_suffix_path` and `s3_enable_hive_compatible_path` options are applied on the
delivery, not the bucket. A common partitioned, analytics-friendly layout:

```hcl
standard_logging_v2_enabled = true
standard_logging_v2 = {
  destination_arn                = "arn:aws:s3:::central-cloudfront-logs"
  output_format                  = "parquet"
  s3_enable_hive_compatible_path = true
  s3_suffix_path                 = "{account-id}/{yyyy}/{MM}/{dd}/{HH}"
}
```

AWS prepends its own managed prefix (`AWSLogs/{account-id}/CloudFront/`); specify
only the custom tail in `s3_suffix_path`.

#### Same account, different stack

No extra setup. When standard logging (v2) is enabled to S3, AWS automatically
adds the required bucket policy for `delivery.logs.amazonaws.com`. Just make sure
the bucket does **not** use the *Bucket owner enforced* object-ownership setting
in a way that blocks the delivery, and reference the bucket's ARN. The bucket can
be managed by any stack in the same account.

#### Cross-account (central logging account)

True cross-account delivery — where the log bucket and the delivery
**destination** live in a different account from the distribution — requires
setup in **both** accounts and is **not** fully managed by this module. This
module creates the delivery source, destination, and delivery **in the site's
account**, which covers same-account delivery (including cross-*region* S3).

For a central logging account you additionally need, in the **destination
account**: an `aws_cloudwatch_log_delivery_destination` plus an
`aws_cloudwatch_log_delivery_destination_policy` that trusts the source
account, and a bucket policy granting `delivery.logs.amazonaws.com` write access
scoped with `aws:SourceAccount` / `aws:SourceArn` conditions. See
[Enable standard logging for cross-account delivery](https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/standard-logging.html#cross-account-delivery).
If you need this module to manage the source side of a cross-account setup
(pointing at a destination ARN in the logging account), open an issue — it is a
deliberate, separate feature.

## Outputs

- `fqdn` - Site FQDN
- `s3_bucket` - S3 bucket name for content
- `cf_id` - CloudFront distribution ID
- `cf_domain_name` - CloudFront distribution domain name

Basic Auth outputs:

- `basic_auth_enabled` - Whether Basic Auth gating is enabled
- `basic_auth_function_arn` - ARN of the Basic Auth CloudFront Function (null when disabled)

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