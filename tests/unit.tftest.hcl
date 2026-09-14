# Unit tests for terraform-aws-website.
# These run with `command = plan` — no real resources are created.

mock_provider "aws" {
  mock_data "aws_route53_zone" {
    defaults = {
      zone_id      = "Z0MOCK123456789"
      name         = "example.com"
      name_servers = ["ns-1.example.com", "ns-2.example.com"]
    }
  }
}

mock_provider "random" {}
mock_provider "time" {}

# The CloudPosse acm-request-certificate and cloudfront-s3-cdn modules do
# for_each over apply-time values internally, which can't be planned under a
# mock provider. Override them with static outputs so these unit tests exercise
# THIS module's logic (gating, merging, guards), not the third-party internals.
override_module {
  target = module.acm_certificate
  outputs = {
    arn                       = "arn:aws:acm:us-east-1:111122223333:certificate/mock"
    domain_validation_options = []
  }
}

override_module {
  target = module.cdn
  outputs = {
    cf_arn                = "arn:aws:cloudfront::111122223333:distribution/E1MOCK"
    cf_id                 = "E1MOCK"
    cf_domain_name        = "dmock.cloudfront.net"
    cf_hosted_zone_id     = "Z2FDTNDATAQYW2"
    cf_identity_iam_arn   = "arn:aws:iam::cloudfront:user/CloudFront Origin Access Identity MOCK"
    s3_bucket             = "mock-origin"
    s3_bucket_arn         = "arn:aws:s3:::mock-origin"
    s3_bucket_domain_name = "mock-origin.s3.amazonaws.com"
  }
}

# --- Baseline: opt-in features off by default ---

run "defaults_create_no_optional_resources" {
  command = plan

  variables {
    fqdn      = "example.com"
    namespace = "test"
    name      = "web"
  }

  assert {
    condition     = length(aws_cloudfront_function.basic_auth) == 0
    error_message = "Basic Auth function must not exist by default"
  }

  assert {
    condition     = length(aws_cloudwatch_log_group.cf_access_logs) == 0
    error_message = "Log group must not exist when standard logging v2 is disabled"
  }

  assert {
    condition     = length(aws_cloudwatch_log_delivery_source.cf_access_logs) == 0
    error_message = "Log delivery source must not exist when standard logging v2 is disabled"
  }
}

# --- Basic Auth ---

run "basic_auth_creates_function_when_enabled" {
  command = plan

  variables {
    fqdn      = "example.com"
    namespace = "test"
    name      = "web"
    basic_auth = {
      enabled  = true
      username = "qa"
      password = "s3cret"
    }
  }

  assert {
    condition     = length(aws_cloudfront_function.basic_auth) == 1
    error_message = "Basic Auth function must exist when basic_auth.enabled is true"
  }

  assert {
    condition     = aws_cloudfront_function.basic_auth[0].runtime == "cloudfront-js-2.0"
    error_message = "Basic Auth function should target the cloudfront-js-2.0 runtime"
  }

  assert {
    condition     = strcontains(aws_cloudfront_function.basic_auth[0].code, base64encode("qa:s3cret"))
    error_message = "Basic Auth function code must embed the base64-encoded credential"
  }
}

# --- Standard logging (v2): module-created CloudWatch Logs group ---

run "logging_creates_log_group_zero_config" {
  command = plan

  variables {
    fqdn                        = "example.com"
    namespace                   = "test"
    name                        = "web"
    standard_logging_v2_enabled = true
  }

  assert {
    condition     = length(aws_cloudwatch_log_group.cf_access_logs) == 1
    error_message = "Zero-config logging must create a CloudWatch Logs log group"
  }

  assert {
    condition     = aws_cloudwatch_log_group.cf_access_logs[0].retention_in_days == 90
    error_message = "Default log group retention should be 90 days"
  }

  assert {
    condition     = aws_cloudwatch_log_delivery_source.cf_access_logs[0].log_type == "ACCESS_LOGS"
    error_message = "Delivery source log_type should be ACCESS_LOGS"
  }
}

# --- Standard logging (v2): external S3 destination, no log group ---

run "logging_external_s3_creates_no_log_group" {
  command = plan

  variables {
    fqdn                        = "example.com"
    namespace                   = "test"
    name                        = "web"
    standard_logging_v2_enabled = true
    standard_logging_v2 = {
      destination_arn = "arn:aws:s3:::my-logs-bucket"
      s3_suffix_path  = "cf/{yyyy}/{MM}/{dd}"
    }
  }

  assert {
    condition     = length(aws_cloudwatch_log_group.cf_access_logs) == 0
    error_message = "No log group should be created when an external destination_arn is supplied"
  }

  assert {
    condition     = aws_cloudwatch_log_delivery_destination.cf_access_logs[0].delivery_destination_configuration[0].destination_resource_arn == "arn:aws:s3:::my-logs-bucket"
    error_message = "Delivery destination should point at the supplied S3 bucket ARN"
  }
}

# --- Standard logging (v2): external non-S3 destination omits S3 config ---

run "logging_external_cwl_omits_s3_config" {
  command = plan

  variables {
    fqdn                        = "example.com"
    namespace                   = "test"
    name                        = "web"
    standard_logging_v2_enabled = true
    standard_logging_v2 = {
      destination_arn = "arn:aws:logs:us-east-1:111122223333:log-group:/my/group:*"
    }
  }

  assert {
    condition     = length(aws_cloudwatch_log_group.cf_access_logs) == 0
    error_message = "No log group should be created when an external destination_arn is supplied"
  }

  assert {
    condition     = aws_cloudwatch_log_delivery_destination.cf_access_logs[0].delivery_destination_configuration[0].destination_resource_arn == "arn:aws:logs:us-east-1:111122223333:log-group:/my/group:*"
    error_message = "Delivery destination should point at the supplied CloudWatch Logs ARN"
  }
}

# --- Consumer-supplied functions on viewer-response coexist with basic_auth ---

run "basic_auth_plus_viewer_response_function_ok" {
  command = plan

  variables {
    fqdn      = "example.com"
    namespace = "test"
    name      = "web"
    basic_auth = {
      enabled  = true
      username = "qa"
      password = "s3cret"
    }
    cloudfront_function_associations = [
      {
        event_type   = "viewer-response"
        function_arn = "arn:aws:cloudfront::111122223333:function/headers"
      },
    ]
  }

  # No precondition failure expected: viewer-response does not collide with
  # the viewer-request Basic Auth function.
  assert {
    condition     = length(aws_cloudfront_function.basic_auth) == 1
    error_message = "Basic Auth should still be created alongside a viewer-response function"
  }
}

# --- Collision guard: basic_auth + consumer viewer-request must fail ---

run "basic_auth_plus_viewer_request_function_fails" {
  command = plan

  variables {
    fqdn      = "example.com"
    namespace = "test"
    name      = "web"
    basic_auth = {
      enabled  = true
      username = "qa"
      password = "s3cret"
    }
    cloudfront_function_associations = [
      {
        event_type   = "viewer-request"
        function_arn = "arn:aws:cloudfront::111122223333:function/redirects"
      },
    ]
  }

  expect_failures = [
    resource.terraform_data.function_association_guard,
  ]
}
