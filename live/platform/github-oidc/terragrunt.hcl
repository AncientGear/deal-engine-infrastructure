terraform {
  source = "git@github.com:AncientGear/infrastructure-modules.git//aws/github-oidc?ref=github-oidc-v0.1.1"
}

include "root" {
  path = find_in_parent_folders("root.hcl")
}

include "env" {
  path           = find_in_parent_folders("env.hcl")
  expose         = true
  merge_strategy = "no_merge"
}

inputs = {
  tags = {
    Environment = include.env.locals.env
    Project     = include.env.locals.project
    Maintainer  = "AncientGear"
    Name        = "github-actions-oidc"
  }
}