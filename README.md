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

## Reference

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.4 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | >= 6.13.0 |
| <a name="requirement_random"></a> [random](#requirement\_random) | >= 2.2 |
| <a name="requirement_time"></a> [time](#requirement\_time) | >= 0.7 |

## Providers

| Name | Version |
| ---- | ------- |
| <a name="provider_aws"></a> [aws](#provider\_aws) | 6.64.0 |
| <a name="provider_terraform"></a> [terraform](#provider\_terraform) | n/a |

## Modules

| Name | Source | Version |
| ---- | ------ | ------- |
| <a name="module_acm_certificate"></a> [acm\_certificate](#module\_acm\_certificate) | cloudposse/acm-request-certificate/aws | 0.18.1 |
| <a name="module_cdn"></a> [cdn](#module\_cdn) | cloudposse/cloudfront-s3-cdn/aws | 2.1.1 |
| <a name="module_this"></a> [this](#module\_this) | cloudposse/label/null | 0.25.0 |

## Resources

| Name | Type |
| ---- | ---- |
| [aws_cloudfront_function.basic_auth](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudfront_function) | resource |
| [aws_cloudwatch_log_delivery.cf_access_logs](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_log_delivery) | resource |
| [aws_cloudwatch_log_delivery_destination.cf_access_logs](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_log_delivery_destination) | resource |
| [aws_cloudwatch_log_delivery_source.cf_access_logs](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_log_delivery_source) | resource |
| [aws_cloudwatch_log_group.cf_access_logs](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_log_group) | resource |
| [terraform_data.function_association_guard](https://registry.terraform.io/providers/hashicorp/terraform/latest/docs/resources/data) | resource |
| [aws_route53_zone.default](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/route53_zone) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_fqdn"></a> [fqdn](#input\_fqdn) | FQDN of the website | `string` | n/a | yes |
| <a name="input_additional_tag_map"></a> [additional\_tag\_map](#input\_additional\_tag\_map) | Additional key-value pairs to add to each map in `tags_as_list_of_maps`. Not added to `tags` or `id`.<br/>This is for some rare cases where resources want additional configuration of tags<br/>and therefore take a list of maps with tag key, value, and additional configuration. | `map(string)` | `{}` | no |
| <a name="input_attributes"></a> [attributes](#input\_attributes) | ID element. Additional attributes (e.g. `workers` or `cluster`) to add to `id`,<br/>in the order they appear in the list. New attributes are appended to the<br/>end of the list. The elements of the list are joined by the `delimiter`<br/>and treated as a single ID element. | `list(string)` | `[]` | no |
| <a name="input_basic_auth"></a> [basic\_auth](#input\_basic\_auth) | Gate the distribution behind HTTP Basic Auth via a CloudFront Function on viewer-request. Intended to keep non-production sites non-public; not a substitute for real authentication (the credential is embedded in the function source and Terraform state). | <pre>object({<br/>    enabled  = optional(bool, false)<br/>    username = optional(string, null)<br/>    password = optional(string, null)<br/>  })</pre> | `{}` | no |
| <a name="input_cloudfront_function_associations"></a> [cloudfront\_function\_associations](#input\_cloudfront\_function\_associations) | Consumer-supplied CloudFront Functions to attach to the default cache behavior (e.g. redirects, header rewrites). The consumer owns the aws\_cloudfront\_function resource and passes its ARN. event\_type is 'viewer-request' or 'viewer-response'. Note: CloudFront allows only one function per event type; a 'viewer-request' entry here conflicts with basic\_auth (fold auth into your own function instead). | <pre>list(object({<br/>    event_type   = string<br/>    function_arn = string<br/>  }))</pre> | `[]` | no |
| <a name="input_context"></a> [context](#input\_context) | Single object for setting entire context at once.<br/>See description of individual variables for details.<br/>Leave string and numeric variables as `null` to use default value.<br/>Individual variable settings (non-null) override settings in context object,<br/>except for attributes, tags, and additional\_tag\_map, which are merged. | `any` | <pre>{<br/>  "additional_tag_map": {},<br/>  "attributes": [],<br/>  "delimiter": null,<br/>  "descriptor_formats": {},<br/>  "enabled": true,<br/>  "environment": null,<br/>  "id_length_limit": null,<br/>  "label_key_case": null,<br/>  "label_order": [],<br/>  "label_value_case": null,<br/>  "labels_as_tags": [<br/>    "unset"<br/>  ],<br/>  "name": null,<br/>  "namespace": null,<br/>  "regex_replace_chars": null,<br/>  "stage": null,<br/>  "tags": {},<br/>  "tenant": null<br/>}</pre> | no |
| <a name="input_default_root_object"></a> [default\_root\_object](#input\_default\_root\_object) | Default root object for CloudFront | `string` | `"index.html"` | no |
| <a name="input_delimiter"></a> [delimiter](#input\_delimiter) | Delimiter to be used between ID elements.<br/>Defaults to `-` (hyphen). Set to `""` to use no delimiter at all. | `string` | `null` | no |
| <a name="input_descriptor_formats"></a> [descriptor\_formats](#input\_descriptor\_formats) | Describe additional descriptors to be output in the `descriptors` output map.<br/>Map of maps. Keys are names of descriptors. Values are maps of the form<br/>`{<br/>   format = string<br/>   labels = list(string)<br/>}`<br/>(Type is `any` so the map values can later be enhanced to provide additional options.)<br/>`format` is a Terraform format string to be passed to the `format()` function.<br/>`labels` is a list of labels, in order, to pass to `format()` function.<br/>Label values will be normalized before being passed to `format()` so they will be<br/>identical to how they appear in `id`.<br/>Default is `{}` (`descriptors` output will be empty). | `any` | `{}` | no |
| <a name="input_enabled"></a> [enabled](#input\_enabled) | Set to false to prevent the module from creating any resources | `bool` | `null` | no |
| <a name="input_environment"></a> [environment](#input\_environment) | ID element. Usually used for region e.g. 'uw2', 'us-west-2', OR role 'prod', 'staging', 'dev', 'UAT' | `string` | `null` | no |
| <a name="input_id_length_limit"></a> [id\_length\_limit](#input\_id\_length\_limit) | Limit `id` to this many characters (minimum 6).<br/>Set to `0` for unlimited length.<br/>Set to `null` for keep the existing setting, which defaults to `0`.<br/>Does not affect `id_full`. | `number` | `null` | no |
| <a name="input_label_key_case"></a> [label\_key\_case](#input\_label\_key\_case) | Controls the letter case of the `tags` keys (label names) for tags generated by this module.<br/>Does not affect keys of tags passed in via the `tags` input.<br/>Possible values: `lower`, `title`, `upper`.<br/>Default value: `title`. | `string` | `null` | no |
| <a name="input_label_order"></a> [label\_order](#input\_label\_order) | The order in which the labels (ID elements) appear in the `id`.<br/>Defaults to ["namespace", "environment", "stage", "name", "attributes"].<br/>You can omit any of the 6 labels ("tenant" is the 6th), but at least one must be present. | `list(string)` | `null` | no |
| <a name="input_label_value_case"></a> [label\_value\_case](#input\_label\_value\_case) | Controls the letter case of ID elements (labels) as included in `id`,<br/>set as tag values, and output by this module individually.<br/>Does not affect values of tags passed in via the `tags` input.<br/>Possible values: `lower`, `title`, `upper` and `none` (no transformation).<br/>Set this to `title` and set `delimiter` to `""` to yield Pascal Case IDs.<br/>Default value: `lower`. | `string` | `null` | no |
| <a name="input_labels_as_tags"></a> [labels\_as\_tags](#input\_labels\_as\_tags) | Set of labels (ID elements) to include as tags in the `tags` output.<br/>Default is to include all labels.<br/>Tags with empty values will not be included in the `tags` output.<br/>Set to `[]` to suppress all generated tags.<br/>**Notes:**<br/>  The value of the `name` tag, if included, will be the `id`, not the `name`.<br/>  Unlike other `null-label` inputs, the initial setting of `labels_as_tags` cannot be<br/>  changed in later chained modules. Attempts to change it will be silently ignored. | `set(string)` | <pre>[<br/>  "default"<br/>]</pre> | no |
| <a name="input_name"></a> [name](#input\_name) | ID element. Usually the component or solution name, e.g. 'app' or 'jenkins'.<br/>This is the only ID element not also included as a `tag`.<br/>The "name" tag is set to the full `id` string. There is no tag with the value of the `name` input. | `string` | `null` | no |
| <a name="input_namespace"></a> [namespace](#input\_namespace) | ID element. Usually an abbreviation of your organization name, e.g. 'eg' or 'cp', to help ensure generated IDs are globally unique | `string` | `null` | no |
| <a name="input_regex_replace_chars"></a> [regex\_replace\_chars](#input\_regex\_replace\_chars) | Terraform regular expression (regex) string.<br/>Characters matching the regex will be removed from the ID elements.<br/>If not set, `"/[^a-zA-Z0-9-]/"` is used to remove all characters other than hyphens, letters and digits. | `string` | `null` | no |
| <a name="input_stage"></a> [stage](#input\_stage) | ID element. Usually used to indicate role, e.g. 'prod', 'staging', 'source', 'build', 'test', 'deploy', 'release' | `string` | `null` | no |
| <a name="input_standard_logging_v2"></a> [standard\_logging\_v2](#input\_standard\_logging\_v2) | Configuration for CloudFront standard logging (v2). Only used when standard\_logging\_v2\_enabled is true; sensible defaults make the zero-config case create a CloudWatch Logs log group. | <pre>object({<br/>    # Destination. Leave destination_arn null to have the module create a<br/>    # CloudWatch Logs log group. Set it to an existing CloudWatch Logs log<br/>    # group, S3 bucket, or Firehose delivery stream ARN to deliver there<br/>    # instead (the module then creates no log group).<br/>    destination_arn = optional(string, null)<br/><br/>    # Only used when the module creates the log group (destination_arn == null).<br/>    log_group_name        = optional(string, null)<br/>    log_group_retention   = optional(number, 90)<br/>    log_group_kms_key_arn = optional(string, null)<br/><br/>    # Output format of delivered logs. One of: json, plain, w3c, raw, parquet.<br/>    output_format = optional(string, "json")<br/><br/>    # Ordered list of access-log record fields to deliver. Leave null to use<br/>    # the AWS default field set.<br/>    record_fields = optional(list(string), null)<br/><br/>    # S3-only delivery options (ignored for CloudWatch Logs / Firehose).<br/>    s3_suffix_path                 = optional(string, null)<br/>    s3_enable_hive_compatible_path = optional(bool, null)<br/>  })</pre> | `{}` | no |
| <a name="input_standard_logging_v2_enabled"></a> [standard\_logging\_v2\_enabled](#input\_standard\_logging\_v2\_enabled) | Enable CloudFront standard logging (v2) via CloudWatch Logs vended log delivery. Independent of the CloudPosse module's legacy access logging. | `bool` | `false` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | Additional tags (e.g. `{'BusinessUnit': 'XYZ'}`).<br/>Neither the tag keys nor the tag values will be modified by this module. | `map(string)` | `{}` | no |
| <a name="input_tenant"></a> [tenant](#input\_tenant) | ID element \_(Rarely used, not included by default)\_. A customer identifier, indicating who this instance of a resource is for | `string` | `null` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_acm_certificate_arn"></a> [acm\_certificate\_arn](#output\_acm\_certificate\_arn) | ACM certificate ARN |
| <a name="output_acm_certificate_domain_validation_options"></a> [acm\_certificate\_domain\_validation\_options](#output\_acm\_certificate\_domain\_validation\_options) | ACM certificate domain validation options |
| <a name="output_basic_auth_enabled"></a> [basic\_auth\_enabled](#output\_basic\_auth\_enabled) | Whether Basic Auth gating is enabled on the distribution. |
| <a name="output_basic_auth_function_arn"></a> [basic\_auth\_function\_arn](#output\_basic\_auth\_function\_arn) | ARN of the Basic Auth CloudFront Function. Null when basic\_auth is disabled. |
| <a name="output_cf_arn"></a> [cf\_arn](#output\_cf\_arn) | CloudFront distribution ARN |
| <a name="output_cf_domain_name"></a> [cf\_domain\_name](#output\_cf\_domain\_name) | CloudFront distribution domain name |
| <a name="output_cf_hosted_zone_id"></a> [cf\_hosted\_zone\_id](#output\_cf\_hosted\_zone\_id) | CloudFront distribution hosted zone ID |
| <a name="output_cf_id"></a> [cf\_id](#output\_cf\_id) | CloudFront distribution ID |
| <a name="output_cf_log_delivery_destination_arn"></a> [cf\_log\_delivery\_destination\_arn](#output\_cf\_log\_delivery\_destination\_arn) | ARN of the CloudWatch Logs delivery destination for CloudFront standard logging (v2). Null when logging is disabled. |
| <a name="output_cf_log_delivery_id"></a> [cf\_log\_delivery\_id](#output\_cf\_log\_delivery\_id) | ID of the CloudWatch Logs delivery for CloudFront standard logging (v2). Null when logging is disabled. |
| <a name="output_cf_log_group_arn"></a> [cf\_log\_group\_arn](#output\_cf\_log\_group\_arn) | ARN of the CloudWatch Logs log group created for CloudFront standard logging (v2). Null when logging is disabled or an external destination is used. |
| <a name="output_cf_log_group_name"></a> [cf\_log\_group\_name](#output\_cf\_log\_group\_name) | Name of the CloudWatch Logs log group created for CloudFront standard logging (v2). Null when logging is disabled or an external destination is used. |
| <a name="output_cf_origin_access_identity_iam_arn"></a> [cf\_origin\_access\_identity\_iam\_arn](#output\_cf\_origin\_access\_identity\_iam\_arn) | CloudFront Origin Access Identity IAM ARN |
| <a name="output_fqdn"></a> [fqdn](#output\_fqdn) | Fully qualified domain name |
| <a name="output_route53_name_servers"></a> [route53\_name\_servers](#output\_route53\_name\_servers) | Route53 hosted zone name servers |
| <a name="output_route53_zone_id"></a> [route53\_zone\_id](#output\_route53\_zone\_id) | Route53 hosted zone ID |
| <a name="output_route53_zone_name"></a> [route53\_zone\_name](#output\_route53\_zone\_name) | Route53 hosted zone name |
| <a name="output_s3_bucket"></a> [s3\_bucket](#output\_s3\_bucket) | S3 bucket name |
| <a name="output_s3_bucket_arn"></a> [s3\_bucket\_arn](#output\_s3\_bucket\_arn) | S3 bucket ARN |
| <a name="output_s3_bucket_domain_name"></a> [s3\_bucket\_domain\_name](#output\_s3\_bucket\_domain\_name) | S3 bucket domain name |
| <a name="output_website_url"></a> [website\_url](#output\_website\_url) | Website URL |
<!-- END_TF_DOCS -->

## Deploy Content

```bash
aws s3 sync ./dist s3://$(terraform output -raw s3_bucket)
aws cloudfront create-invalidation --distribution-id $(terraform output -raw cf_id) --paths '/*'
```