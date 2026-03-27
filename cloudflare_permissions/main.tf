terraform {
  required_providers {
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 5.0"
    }
  }
}

data "cloudflare_api_token_permission_groups_list" "zone_permissions" {
  scope = "com.cloudflare.api.account.zone"
}

output "permission_groups_by_name" {
  value = {
    for permission_group in data.cloudflare_api_token_permission_groups_list.zone_permissions.result :
    permission_group.name => permission_group
  }
}
