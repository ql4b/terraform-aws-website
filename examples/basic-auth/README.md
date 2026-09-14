# Basic Auth example

Deploys a website gated behind HTTP Basic Auth via a CloudFront Function on
viewer-request — useful to keep a QA/staging site non-public.

```bash
terraform apply \
  -var 'fqdn=qa.example.com' \
  -var 'auth_username=qa' \
  -var 'auth_password=s3cret'
```

**This is a coarse gate, not real authentication.** The credential is
base64-encoded into the CloudFront Function source and stored in Terraform
state. Use it to keep casual visitors and crawlers out of a dev/QA site, not to
protect sensitive data.

Because Basic Auth occupies the `viewer-request` event, you cannot also pass a
`viewer-request` function via `cloudfront_function_associations` (the module
fails at plan with a clear message). To combine auth with redirects, fold the
auth check into your own function — see the [module README](../../).
