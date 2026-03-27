terraform {
  required_providers {
    cloudflare = {
      source = "cloudflare/cloudflare"
    }
  }
}

variable "name" {
  type = string
}

variable "writable_cloudflare_zones" {
  type = list(object({
    id   = string
    name = string
  }))
}

variable "cloudflare_account_id" {
  type = string
}

module "cloudflare_permissions" {
  source = "github.com/neinteractiveliterature/neil-terraform-modules//cloudflare_permissions?ref=v1.0.0"
}

resource "cloudflare_account_token" "deploy" {
  name = var.name
  account_id = var.cloudflare_account_id
  policies = [
    {
      effect = "allow"
      permission_groups = [
        { id = module.cloudflare_permissions.permission_groups_by_name["DNS Read"].id },
        { id = module.cloudflare_permissions.permission_groups_by_name["Zone Read"].id },
      ]
      resources = jsonencode({
        "com.cloudflare.api.account.${var.cloudflare_account_id}" = {
          "com.cloudflare.api.account.zone.*" = "*"
        }
      })
    },
    {
      effect = "allow"
      permission_groups = [
        { id = module.cloudflare_permissions.permission_groups_by_name["DNS Write"].id },
      ]
      resources = jsonencode({
        for zone in var.writable_cloudflare_zones:
        "com.cloudflare.api.account.zone.${zone.id}" => "*"
      })
    }
  ]
}

output "cloudflare_api_token" {
  value = cloudflare_account_token.deploy.value
}

output "cloudflare_account_id" {
  value = var.cloudflare_account_id
}
