terraform {
  source = "git@github.com:AncientGear/infrastructure-modules.git//aws/acm-cloudflare-certificate?ref=acm-cloudflare-certificate-v0.0.2"
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
  cloudflare_zone_id        = "e9de4cd1676a312ab2397d27977d00ab"
  tags = {
    Environment = include.env.locals.env
    Project     = include.env.locals.project
    Maintainer  = "AncientGear"
    Name        = "${include.env.locals.env}-${include.env.locals.project}-alb-certificate"
  }
}
