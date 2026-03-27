terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
    }
    cloudflare = {
      source = "cloudflare/cloudflare"
    }
  }
}

variable "origin_id" {
  type = string
}

variable "domain_name" {
  type = string
}

variable "compress" {
  type    = bool
  default = false
}

variable "alternative_names" {
  type    = list(string)
  default = []
}

variable "validation_method" {
  type    = string
  default = "DNS"
}

variable "origin_domain_name" {
  type = string
}

variable "origin_protocol_policy" {
  type    = string
  default = "http-only"
}

variable "default_root_object" {
  type    = string
  default = null
}

variable "add_security_headers_arn" {
  type = string
}

variable "cloudflare_zone" {
  type = object({
    id   = string
    name = string
  })
  default = null
}

resource "aws_acm_certificate_validation" "cert_validation" {
  certificate_arn         = aws_acm_certificate.cloudfront_cert.arn
  validation_record_fqdns = [for record in cloudflare_dns_record.cert_validation_records : "${record.name}."]
}

resource "aws_acm_certificate" "cloudfront_cert" {
  domain_name               = var.domain_name
  validation_method         = var.validation_method
  subject_alternative_names = var.alternative_names

  options {
    certificate_transparency_logging_preference = "ENABLED"
  }
}

resource "aws_cloudfront_distribution" "cloudfront_distribution" {
  enabled = true

  origin {
    domain_name = var.origin_domain_name
    origin_id   = var.origin_id

    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = var.origin_protocol_policy
      origin_ssl_protocols   = ["TLSv1", "TLSv1.1", "TLSv1.2"]
    }
  }

  aliases             = concat([var.domain_name], var.alternative_names)
  is_ipv6_enabled     = true
  default_root_object = var.default_root_object

  default_cache_behavior {
    cache_policy_id          = "658327ea-f89d-4fab-a63d-7e88639e58f6" # Managed-CachingOptimized
    origin_request_policy_id = "59781a5b-3903-41f3-afcb-af62929ccde1" # Managed-CORS-CustomOrigin

    allowed_methods        = ["GET", "HEAD"]
    cached_methods         = ["GET", "HEAD"]
    target_origin_id       = var.origin_id
    viewer_protocol_policy = "redirect-to-https"
    compress               = var.compress

    lambda_function_association {
      event_type   = "origin-response"
      include_body = false
      lambda_arn   = var.add_security_headers_arn
    }
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    acm_certificate_arn      = aws_acm_certificate.cloudfront_cert.arn
    minimum_protocol_version = "TLSv1.1_2016"
    ssl_support_method       = "sni-only"
  }
}

resource "cloudflare_dns_record" "cert_validation_records" {
  for_each = {
    for dvo in(var.cloudflare_zone != null ? aws_acm_certificate.cloudfront_cert.domain_validation_options : []) : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  }

  name    = trimsuffix(each.value.name, ".")
  content = trimsuffix(each.value.record, ".")
  type    = each.value.type
  zone_id = var.cloudflare_zone.id
  proxied = false
  ttl     = 1
}

output "cloudfront_distribution" {
  value = aws_cloudfront_distribution.cloudfront_distribution
}

output "acm_certificate" {
  value = aws_acm_certificate.cloudfront_cert
}

output "cert_validation" {
  value = aws_acm_certificate_validation.cert_validation
}

output "cert_validation_records" {
  value = cloudflare_dns_record.cert_validation_records
}
