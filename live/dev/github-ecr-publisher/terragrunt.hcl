terraform {
  source = "git@github.com:AncientGear/infrastructure-modules.git//aws/github-ecr-publisher?ref=github-ecr-publisher-v0.2.0"
}

include "root" {
  path = find_in_parent_folders("root.hcl")
}

include "env" {
  path           = find_in_parent_folders("env.hcl")
  expose         = true
  merge_strategy = "no_merge"
}

dependency "github_oidc" {
  config_path = "../../platform/github-oidc"
}

dependency "ecr" {
  config_path = "../ecr"
}

inputs = {
  role_name          = "dealengine-dev-github-ecr-publisher"
  oidc_provider_arn  = dependency.github_oidc.outputs.arn
  ecr_repository_arn = dependency.ecr.outputs.repository_arn

  github_subject = "repo:AncientGear@24779392/deal-engine-tickets-be@1389541212:ref:refs/heads/dev"

  tags = {
    Environment = include.env.locals.env
    Project     = include.env.locals.project
    Maintainer  = "AncientGear"
    Name        = "dealengine-dev-github-ecr-publisher"
  }
}