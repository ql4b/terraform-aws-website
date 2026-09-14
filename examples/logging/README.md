# Logging example

Deploys a website with CloudFront standard logging (v2) delivering access logs
to an existing S3 bucket, using partitioned, Hive-compatible object paths
suitable for Athena/Glue.

```bash
terraform apply \
  -var 'fqdn=example.com' \
  -var 'log_bucket_arn=arn:aws:s3:::my-central-cloudfront-logs'
```

The module does **not** create the log bucket — you pass an existing bucket
ARN, so it can live in a different Terraform stack or AWS account. For a
same-account bucket, AWS automatically adds the required
`delivery.logs.amazonaws.com` bucket policy when v2 logging is enabled.

To create a CloudWatch Logs log group instead of using S3, omit
`destination_arn` (the zero-config path). See the [module README](../../) for
the full `standard_logging_v2` options and the cross-account notes.
