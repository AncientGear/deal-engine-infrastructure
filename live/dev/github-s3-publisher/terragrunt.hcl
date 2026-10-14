terraform {
  source = "git@github.com:AncientGear/infrastructure-modules.git//aws/github-s3-publisher?ref=github-s3-publisher-v0.1.1"
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

dependency "s3" {
  config_path = "../s3-cloudfront"
}

inputs = {
  role_name         = "dealengine-dev-github-s3-publisher"
  oidc_provider_arn = dependency.github_oidc.outputs.arn
  bucket_arn        = dependency.s3.outputs.bucket_arn
  enable_promotion            = true
  cloudfront_distribution_arn = "arn:aws:cloudfront::989200477899:distribution/E9HSDX6N409DP"

  github_subject = "repo:AncientGear@24779392/deal-engine-tickets-frontend@1389745547:ref:refs/heads/dev"

  tags = {
    Environment = include.env.locals.env
    Project     = include.env.locals.project
    Maintainer  = "AncientGear"
    Name        = "dealengine-dev-github-s3-publisher"
  }
}