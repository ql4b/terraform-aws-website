# Simple example

Deploys a public website with [terraform-aws-website](../../) using all
defaults: CloudFront + S3 origin, an ACM certificate, and a Route53 alias.

A Route53 hosted zone whose name equals `fqdn` must already exist.

```bash
terraform apply -var 'fqdn=example.com'
```

Then deploy content:

```bash
aws s3 sync ./dist "s3://$(terraform output -raw s3_bucket)"
aws cloudfront create-invalidation \
  --distribution-id "$(terraform output -raw cf_id)" --paths '/*'
```

See the [module README](../../) for all inputs and the other examples.
