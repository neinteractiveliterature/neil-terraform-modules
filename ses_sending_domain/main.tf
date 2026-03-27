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

variable "cloudflare_zone" {
  type = object({
    id   = string
    name = string
  })
  default = null
}

locals {
  domain_name = trimsuffix(var.cloudflare_zone.name, ".")
}

resource "aws_ses_domain_identity" "domain_identity" {
  domain = local.domain_name
}

resource "aws_ses_domain_dkim" "domain_dkim" {
  domain = local.domain_name
}

resource "cloudflare_dns_record" "amazonses_verification_record" {
  count = var.cloudflare_zone != null ? 1 : 0

  zone_id = var.cloudflare_zone.id
  name    = "_amazonses.${local.domain_name}"
  type    = "TXT"
  content = aws_ses_domain_identity.domain_identity.verification_token
  ttl     = 1
}

resource "cloudflare_dns_record" "amazonses_dkim_record" {
  count = var.cloudflare_zone != null ? 3 : 0

  zone_id = var.cloudflare_zone.id
  name    = "${element(aws_ses_domain_dkim.domain_dkim.dkim_tokens, count.index)}._domainkey.${aws_ses_domain_dkim.domain_dkim.domain}"
  type    = "CNAME"
  content = "${element(aws_ses_domain_dkim.domain_dkim.dkim_tokens, count.index)}.dkim.amazonses.com"
  ttl     = 1
}
