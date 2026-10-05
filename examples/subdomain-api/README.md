# Subdomain + API example

Deploys a website on a subdomain whose hosted zone is created (and delegated
from the parent zone) in the same configuration, routes `/v1/*` to a custom
origin such as a Lambda Function URL, and serves a custom 404 page for
missing objects.

```bash
terraform apply \
  -var 'fqdn=app.example.com' \
  -var 'parent_zone_name=example.com' \
  -var 'api_origin_domain=abc123.lambda-url.us-east-1.on.aws'
```

`route53_zone_id` is what lets the module use a zone created here: without it,
the module looks the zone up by `fqdn` at plan time, which fails before the
zone exists.

See the [module README](../../) for all inputs and the other examples.
