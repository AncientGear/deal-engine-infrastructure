terraform {
  source = "git@github.com:AncientGear/infrastructure-modules.git//aws/s3-for-cloudfront?ref=s3-for-cloudfront-v0.1.0"
}

include "root" {
  path = find_in_parent_folders("root.hcl")
}

include "env" {
  path           = find_in_parent_folders("env.hcl")
  expose         = true
  merge_strategy = "no_merge"
}

locals {
  Project     = "deal-engine-ticket-manager"
  Environment = include.env.locals.env
}

inputs = {
  bucket_prefix_name = "${local.Project}-${local.Environment}"
  tags = {
    Name        = "${local.Project}-${local.Environment}"
    Project     = local.Project
    Environment = local.Environment
  }
}

