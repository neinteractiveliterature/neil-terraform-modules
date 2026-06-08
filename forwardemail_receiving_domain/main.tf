terraform {
  required_providers {
    cloudflare = {
      source = "cloudflare/cloudflare"
    }
  }
}

variable "zone_id" {
  type     = string
  nullable = false
}

variable "name" {
  type     = string
  nullable = false
}

variable "verification_code" {
  type     = string
  nullable = false
}

resource "cloudflare_dns_record" "mx1" {
  zone_id  = var.zone_id
  name     = var.name
  type     = "MX"
  content  = "mx1.forwardemail.net"
  ttl      = 1
  priority = 10
}

resource "cloudflare_dns_record" "mx2" {
  zone_id  = var.zone_id
  name     = var.name
  type     = "MX"
  content  = "mx2.forwardemail.net"
  ttl      = 1
  priority = 10
}

resource "cloudflare_dns_record" "verification_txt" {
  zone_id = var.zone_id
  name    = var.name
  type    = "TXT"
  content = "\"forward-email-site-verification=${var.verification_code}\""
  ttl     = 3600
}
