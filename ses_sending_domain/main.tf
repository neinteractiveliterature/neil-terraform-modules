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

variable "zone_id" {
  type    = string
  default = null
}

data "cloudflare_zone" "this" {
  count   = var.zone_id != null ? 1 : 0
  zone_id = var.zone_id
}

locals {
  domain_name = var.zone_id != null ? trimsuffix(data.cloudflare_zone.this[0].name, ".") : null
}

resource "aws_ses_domain_identity" "domain_identity" {
  domain = local.domain_name
}

resource "aws_ses_domain_dkim" "domain_dkim" {
  domain = local.domain_name
}

resource "cloudflare_dns_record" "amazonses_verification_record" {
  count = var.zone_id != null ? 1 : 0

  zone_id = var.zone_id
  name    = "_amazonses.${local.domain_name}"
  type    = "TXT"
  content = aws_ses_domain_identity.domain_identity.verification_token
  ttl     = 1
}

resource "cloudflare_dns_record" "amazonses_dkim_record" {
  count = var.zone_id != null ? 3 : 0

  zone_id = var.zone_id
  name    = "${element(aws_ses_domain_dkim.domain_dkim.dkim_tokens, count.index)}._domainkey.${aws_ses_domain_dkim.domain_dkim.domain}"
  type    = "CNAME"
  content = "${element(aws_ses_domain_dkim.domain_dkim.dkim_tokens, count.index)}.dkim.amazonses.com"
  ttl     = 1
}
