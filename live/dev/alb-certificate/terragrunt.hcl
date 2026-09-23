terraform {
  source = "git@github.com:AncientGear/infrastructure-modules.git//aws/acm-cloudflare-certificate?ref=acm-cloudflare-certificate-v0.0.1"
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
  domain_name               = "alb-${include.env.locals.env}-${include.env.locals.project}.saul-tzakum.tech"
  subject_alternative_names = ["*.alb-${include.env.locals.env}-${include.env.locals.project}.saul-tzakum.tech"]
  cloudflare_zone_id        = "f3e7c1b0d8a2e4c5b6a7c8d9e0f1a2b3"
  tags = {
    Environment = include.env.locals.env
    Project     = include.env.locals.project
    Maintainer  = "AncientGear"
    Name        = "${include.env.locals.env}-${include.env.locals.project}-alb-certificate"
  }
}
