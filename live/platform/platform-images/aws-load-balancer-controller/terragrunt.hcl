terraform {
  source = "git@github.com:AncientGear/infrastructure-modules.git//aws/ecr?ref=ecr-v0.0.3"
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
  name                 = "platform/aws-load-balancer-controller"
  image_tag_mutability = "IMMUTABLE"

  tags = {
    Environment = include.env.locals.env
    Project     = include.env.locals.project
    Maintainer  = "AncientGear"
    Name        = "platform-aws-load-balancer-controller"
  }
}
