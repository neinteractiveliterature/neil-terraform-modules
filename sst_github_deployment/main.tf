terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
    }
    github = {
      source = "integrations/github"
    }
  }
}

variable "app_name" {
  type        = string
  description = "Application name. Used to name IAM resources (groups, users, roles). Deprecated for IAM resource scoping — use resource_name_pattern instead."
}

variable "resource_name_pattern" {
  type        = string
  default     = null
  description = "Glob pattern used to scope IAM policy resource ARNs (e.g. \"myapp*-production-*\"). If not set, defaults to \"$${app_name}-production-*\". Use this when SST truncates the app name in resource names."
}

locals {
  resource_name_pattern = var.resource_name_pattern != null ? var.resource_name_pattern : "${var.app_name}-production-*"
}

variable "cloudflare_account_id" {
  type = string
}

variable "github_repository" {
  type = object({
    name = string
    full_name = string
  })
}

variable "oidc_provider_arn" {
  type = string
}

variable "writable_cloudflare_zones" {
  type = list(object({
    id   = string
    name = string
  }))
}

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

resource "aws_iam_group" "production" {
  name = "${var.app_name}-production"
}

resource "aws_iam_group_policy" "production" {
  name  = "${var.app_name}-production"
  group = aws_iam_group.production.name

  policy = <<-EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": "ses:SendRawEmail",
      "Resource": "*"
    }
  ]
}
EOF
}

resource "aws_iam_user" "production" {
  name = "${var.app_name}-production"
}

resource "aws_iam_user_group_membership" "production" {
  user   = aws_iam_user.production.name
  groups = [aws_iam_group.production.name]
}

resource "aws_iam_access_key" "production" {
  user = aws_iam_user.production.name
}

resource "aws_iam_role" "deploy" {
  name = "${var.app_name}-deploy"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"

    Statement = [{
      Action = "sts:AssumeRoleWithWebIdentity"
      Effect = "Allow"

      Condition = {
        StringLike = {
          "token.actions.githubusercontent.com:sub" : "repo:${var.github_repository.full_name}:*"
        }
      }

      Principal = {
        Federated = var.oidc_provider_arn
      }
    }]
  })
}

resource "aws_iam_role_policy" "deploy" {
  role = aws_iam_role.deploy.name

  policy = jsonencode({
    Version = "2012-10-17"

    Statement = [
      {
        "Sid" : "ManageBootstrapStateBucket",
        "Effect" : "Allow",
        "Action" : [
          "s3:CreateBucket",
          "s3:PutBucketVersioning",
          "s3:PutBucketNotification",
          "s3:DeleteObject",
          "s3:GetObject",
          "s3:ListBucket",
          "s3:PutObject"
        ],
        "Resource" : [
          "arn:aws:s3:::sst-state-*"
        ]
      },
      {
        "Sid" : "ManageBootstrapAssetBucket",
        "Effect" : "Allow",
        "Action" : [
          "s3:CreateBucket",
          "s3:PutBucketVersioning",
          "s3:DeleteObject",
          "s3:GetObject",
          "s3:GetObjectTagging",
          "s3:ListBucket",
          "s3:PutObject",
          "s3:PutObjectTagging",
        ],
        "Resource" : [
          "arn:aws:s3:::sst-asset-*"
        ]
      },
      {
        "Sid" : "ManageBootstrapECRRepo",
        "Effect" : "Allow",
        "Action" : [
          "ecr:CreateRepository",
          "ecr:DescribeRepositories"
        ],
        "Resource" : [
          "arn:aws:ecr:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:repository/sst-asset"
        ]
      },
      {
        "Sid" : "ManageBootstrapSSMParameter",
        "Effect" : "Allow",
        "Action" : [
          "ssm:GetParameter",
          "ssm:GetParameters",
          "ssm:PutParameter"
        ],
        "Resource" : [
          "arn:aws:ssm:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:parameter/sst/passphrase/*",
          "arn:aws:ssm:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:parameter/sst/bootstrap"
        ]
      },
      {
        "Sid" : "ManageApplicationProductionBucket",
        "Effect" : "Allow",
        "Action" : [
          "s3:CreateBucket",
          "s3:PutBucketVersioning",
          "s3:DeleteObject",
          "s3:GetObject",
          "s3:ListBucket",
          "s3:PutObject",
          "s3:GetObjectTagging",
          "s3:PutObjectTagging",
          "s3:GetBucketTagging",
          "s3:GetBucketPolicy",
          "s3:GetBucketAcl",
          "s3:GetBucketCORS",
          "s3:GetBucketWebsite",
          "s3:GetBucketVersioning",
          "s3:GetAccelerateConfiguration",
          "s3:GetBucketRequestPayment",
          "s3:GetBucketLogging",
          "s3:GetLifecycleConfiguration",
          "s3:GetReplicationConfiguration",
          "s3:GetEncryptionConfiguration",
          "s3:GetBucketObjectLockConfiguration"
        ],
        "Resource" : [
          "arn:aws:s3:::${local.resource_name_pattern}",
          "arn:aws:s3:::sst-asset-*"
        ]
      },
      {
        "Sid" : "ManageApplicationLogGroups",
        "Effect" : "Allow",
        "Action" : [
          "logs:CreateLogGroup",
          "logs:TagResource"
        ],
        "Resource" :[
          "arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:log-group:/aws/lambda/${local.resource_name_pattern}:log-stream:"
        ]
      },
      {
        "Sid" : "ManageLambdaFunctions",
        "Effect" : "Allow",
        "Action" : [
          "lambda:CreateFunction",
          "lambda:GetFunction",
          "lambda:UpdateFunctionCode",
          "lambda:ListVersionsByFunction",
          "lambda:GetFunctionCodeSigningConfig",
          "lambda:InvokeFunction",
          "lambda:UpdateFunctionConfiguration",
          "lambda:AddPermission",
          "lambda:TagResource"
        ],
        "Resource" : [
          "arn:aws:lambda:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:function:*"
        ]
      },
      {
        "Sid" : "ManageIAMRoles",
        "Effect" : "Allow",
        "Action" : [
          "iam:PassRole"
        ],
        "Resource" : [
          "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/${local.resource_name_pattern}"
        ]
      },
      {
        "Sid" : "ManageCloudfrontDistributions",
        "Effect" : "Allow",
        "Action" : [
          "cloudfront:CreateInvalidation"
        ],
        "Resource" : [
          "*"
        ]
      },
      {
        "Sid": "ManageCloudfrontCachePolicies",
        "Effect": "Allow",
        "Action": [
          "cloudfront:CreateCachePolicy",
          "cloudfront:GetCachePolicy",
          "cloudfront:UpdateCachePolicy"
        ],
        "Resource": [
          "arn:aws:cloudfront::${data.aws_caller_identity.current.account_id}:cache-policy/*"
        ]
      },
      {
        "Sid": "ManageCloudfrontKVStores",
        "Effect": "Allow",
        "Action": [
          "cloudfront:CreateKeyValueStore",
          "cloudfront:DescribeKeyValueStore",
          "cloudfront-keyvaluestore:CreateKeyValueStore",
          "cloudfront-keyvaluestore:DescribeKeyValueStore",
          "cloudfront-keyvaluestore:UpdateKeys"
        ],
        "Resource": [
          "arn:aws:cloudfront::${data.aws_caller_identity.current.account_id}:key-value-store/*"
        ]
      },
      {
        "Sid" : "ManageCloudfrontFunctions",
        "Effect" : "Allow",
        "Action" : [
          "cloudfront:CreateFunction",
          "cloudfront:DescribeFunction",
          "cloudfront:GetFunction",
          "cloudfront:UpdateFunction",
          "cloudfront:PublishFunction"
        ],
        "Resource" : [
          "arn:aws:cloudfront::${data.aws_caller_identity.current.account_id}:function/*"
        ]
      },
      {
        "Sid" : "ManageACMCertificates",
        "Effect" : "Allow",
        "Action" : [
          "acm:RequestCertificate",
          "acm:DescribeCertificate",
          "acm:DeleteCertificate",
          "acm:AddTagsToCertificate",
          "acm:ListTagsForCertificate"
        ],
        "Resource" : [
          "arn:aws:acm:*:${data.aws_caller_identity.current.account_id}:certificate/*"
        ]
      },
    ]
  })
}

module "cloudflare_deploy_token" {
  source = "github.com/neinteractiveliterature/neil-terraform-modules//sst_cloudflare_deploy_token?ref=v1.0.0"

  name = "${var.app_name} deploy token"
  writable_cloudflare_zones = var.writable_cloudflare_zones
  cloudflare_account_id = var.cloudflare_account_id
}

resource "github_actions_secret" "cloudflare_api_token" {
  repository      = var.github_repository.name
  secret_name     = "CLOUDFLARE_API_TOKEN"
  value = module.cloudflare_deploy_token.cloudflare_api_token
}

resource "github_actions_secret" "cloudflare_account_id" {
  repository      = var.github_repository.name
  secret_name     = "CLOUDFLARE_ACCOUNT_ID"
  value = module.cloudflare_deploy_token.cloudflare_account_id
}

resource "github_actions_secret" "aws_oidc_role" {
  repository      = var.github_repository.name
  secret_name     = "AWS_OIDC_ROLE"
  value = aws_iam_role.deploy.arn
}

output "cloudflare_api_token" {
  value = module.cloudflare_deploy_token.cloudflare_api_token
}

output "cloudflare_account_id" {
  value = module.cloudflare_deploy_token.cloudflare_account_id
}

output "smtp_url" {
  sensitive = true
  value = "smtp://${urlencode(aws_iam_access_key.production.id)}:${urlencode(aws_iam_access_key.production.ses_smtp_password_v4)}@email-smtp.${data.aws_region.current.name}.amazonaws.com"
}

output "aws_deploy_oidc_role" {
  value = aws_iam_role.deploy.arn
}
