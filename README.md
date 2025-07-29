# terraform-aws-website

> Complete website infrastructure from just a domain name

Terraform module that creates a production-ready website with CloudFront CDN, S3 hosting, SSL certificate, and Route53 DNS configuration.

## Features

- **CloudFront CDN** with S3 origin
- **SSL Certificate** via ACM with automatic validation
- **Route53 DNS** alias configuration
- **HTTPS redirect** enforced
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

## Outputs

- `s3_bucket` - S3 bucket name for content
- `cf_id` - CloudFront distribution ID
- `website_url` - Complete website URL

## Deploy Content

```bash
aws s3 sync ./dist s3://$(terraform output -raw s3_bucket)
aws cloudfront create-invalidation --distribution-id $(terraform output -raw cf_id) --paths '/*'
```