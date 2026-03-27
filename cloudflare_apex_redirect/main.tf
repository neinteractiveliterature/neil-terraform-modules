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

variable "redirect_destination_hostname" {
  type = string
}

variable "redirect_destination_protocol" {
  type = string
}

variable "redirect_destination_path" {
  type    = string
  default = null
}

variable "alternative_names" {
  type    = list(string)
  default = []
}

variable "cloudflare_zone" {
  nullable = false
  type = object({
    id   = string
    name = string
  })
}

variable "domain_name" {
  type    = string
  default = null
}

locals {
  domain_name = (
    var.domain_name != null ?
    var.domain_name :
    var.cloudflare_zone.name
  )
}

resource "aws_s3_bucket" "redirect_bucket" {
  bucket = local.domain_name
}

resource "aws_s3_bucket_ownership_controls" "redirect_bucket" {
  bucket = aws_s3_bucket.redirect_bucket.id
  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_public_access_block" "redirect_bucket" {
  bucket = aws_s3_bucket.redirect_bucket.id

  block_public_policy     = false
  restrict_public_buckets = false
}

resource "aws_s3_bucket_policy" "redirect_bucket" {
  bucket = aws_s3_bucket.redirect_bucket.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Principal = "*"
        Action = [
          "s3:GetObject"
        ]
        Resource = [
          "${aws_s3_bucket.redirect_bucket.arn}/*"
        ]
      }
    ]
  })
}

resource "aws_s3_bucket_website_configuration" "redirect_bucket" {
  bucket = aws_s3_bucket.redirect_bucket.bucket

  index_document {
    suffix = "index.html"
  }

  routing_rule {
    redirect {
      host_name               = var.redirect_destination_hostname
      protocol                = var.redirect_destination_protocol
      http_redirect_code      = 302
      replace_key_prefix_with = var.redirect_destination_path
    }
  }
}

resource "cloudflare_dns_record" "apex_alias" {
  zone_id = var.cloudflare_zone.id
  name    = local.domain_name
  type    = "CNAME"
  proxied = true
  content = aws_s3_bucket_website_configuration.redirect_bucket.website_endpoint
  ttl     = 1
}

resource "cloudflare_dns_record" "alternative_name_cname" {
  for_each = toset(var.alternative_names)
  zone_id  = var.cloudflare_zone.id
  name     = each.key
  type     = "CNAME"
  proxied  = true
  content  = var.cloudflare_zone.name
  ttl      = 1
}

output "redirect_bucket" {
  value = aws_s3_bucket.redirect_bucket
}

output "apex_alias_record" {
  value = cloudflare_dns_record.apex_alias
}
