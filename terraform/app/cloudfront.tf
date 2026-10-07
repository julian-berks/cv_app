provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"
}

resource "aws_acm_certificate" "cv" {
  count             = var.container_deployed ? 1 : 0
  provider          = aws.us_east_1
  domain_name       = var.domain_name
  validation_method = "DNS"
  tags              = var.tags

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_acm_certificate_validation" "cv" {
  count           = var.container_deployed ? 1 : 0
  provider        = aws.us_east_1
  certificate_arn = aws_acm_certificate.cv[0].arn
  validation_record_fqdns = [
    for option in aws_acm_certificate.cv[0].domain_validation_options : option.resource_record_name
  ]
}

resource "aws_cloudfront_origin_access_control" "lambda" {
  count                             = var.container_deployed ? 1 : 0
  name                              = "${var.name}-lambda-oac"
  description                       = "Allow CloudFront to invoke the CV Lambda URL."
  origin_access_control_origin_type = "lambda"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

resource "aws_wafv2_web_acl" "cloudfront" {
  provider = aws.us_east_1
  name     = "${var.name}-CloudFront-WAF"
  scope    = "CLOUDFRONT"
  tags     = var.tags

  default_action {
    allow {}
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "${var.name}-CloudFront-WAF"
    sampled_requests_enabled   = true
  }

  dynamic "rule" {
    for_each = {
      AWSManagedRulesAmazonIpReputationList = 0
      AWSManagedRulesCommonRuleSet          = 1
      AWSManagedRulesKnownBadInputsRuleSet  = 2
    }

    content {
      name     = "AWS-${rule.key}"
      priority = rule.value

      override_action {
        count {}
      }

      statement {
        managed_rule_group_statement {
          name        = rule.key
          vendor_name = "AWS"
        }
      }

      visibility_config {
        cloudwatch_metrics_enabled = true
        metric_name                = "${var.name}-CloudFront-WAF-AWS-${rule.key}"
        sampled_requests_enabled   = true
      }
    }
  }

  rule {
    name     = "RateLimitPerIP"
    priority = 3

    action {
      block {}
    }

    statement {
      # The Free plan only supports plain per-IP limits over 5 minutes; the 10 questions per minute limit is in app.py.
      rate_based_statement {
        limit                 = var.waf_requests_per_5_minutes
        evaluation_window_sec = 300
        aggregate_key_type    = "IP"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${var.name}-CloudFront-WAF-RateLimitPerIP"
      sampled_requests_enabled   = true
    }
  }
}

resource "aws_cloudfront_distribution" "cv" {
  count           = var.container_deployed ? 1 : 0
  enabled         = true
  is_ipv6_enabled = true
  comment         = "${var.name} CV application"
  aliases         = [var.domain_name]
  price_class     = "PriceClass_All"
  tags            = var.tags
  web_acl_id      = aws_wafv2_web_acl.cloudfront.arn

  origin {
    domain_name              = trimsuffix(trimprefix(module.function[0].function_url, "https://"), "/")
    origin_id                = "${var.name}-lambda-function-url"
    origin_access_control_id = aws_cloudfront_origin_access_control.lambda[0].id

    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "https-only"
      origin_ssl_protocols   = ["TLSv1.2"]
    }
  }

  default_cache_behavior {
    target_origin_id         = "${var.name}-lambda-function-url"
    viewer_protocol_policy   = "redirect-to-https"
    allowed_methods          = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods           = ["GET", "HEAD", "OPTIONS"]
    compress                 = true
    cache_policy_id          = "4135ea2d-6df8-44a3-9df3-4b5a84be39ad"
    origin_request_policy_id = "b689b0a8-53d0-40ab-baf2-68738e2966ac"
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    acm_certificate_arn      = aws_acm_certificate_validation.cv[0].certificate_arn
    ssl_support_method       = "sni-only"
    minimum_protocol_version = "TLSv1.2_2021"
  }

  depends_on = [aws_acm_certificate_validation.cv]
}

resource "aws_lambda_permission" "cloudfront_url" {
  count                  = var.container_deployed ? 1 : 0
  statement_id           = "AllowCloudFrontFunctionUrl"
  action                 = "lambda:InvokeFunctionUrl"
  function_name          = module.function[0].function_name
  principal              = "cloudfront.amazonaws.com"
  source_arn             = aws_cloudfront_distribution.cv[0].arn
  function_url_auth_type = "AWS_IAM"
}

resource "aws_lambda_permission" "cloudfront_invoke" {
  count                    = var.container_deployed ? 1 : 0
  statement_id             = "AllowCloudFrontInvokeFunctionUrl"
  action                   = "lambda:InvokeFunction"
  function_name            = module.function[0].function_name
  principal                = "cloudfront.amazonaws.com"
  source_arn               = aws_cloudfront_distribution.cv[0].arn
  invoked_via_function_url = true
}

