terraform {
  source = "git@github.com:AncientGear/infrastructure-modules.git//aws/vpc?ref=vpc-v0.1.0"
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
  env                 = include.env.locals.env
  vpc_cidr_block      = "10.0.0.0/16"
  azs                 = ["us-east-1a", "us-east-1b"]
  private_app_subnets = ["10.0.0.0/19", "10.0.32.0/19"]
  public_subnets      = ["10.0.64.0/22", "10.0.68.0/22"]

  private_db_subnets = ["10.0.96.0/28", "10.0.96.16/28"]

  private_app_subnet_tags = {
    "kubernetes.io/role/internal-elb"                      = 1
    "kubernetes.io/cluster/${include.env.locals.env}-demo" = "owned"
  }

  public_subnet_tags = {
    "kubernetes.io/role/elb"                               = 1
    "kubernetes.io/cluster/${include.env.locals.env}-demo" = "owned"
  }

  private_db_subnet_tags = {
    env     = include.env.locals.env
    project = "demo"
  }

  vpc_tags = {
    Name    = "${include.env.locals.env}-demo"
    env     = include.env.locals.env
    project = "demo"
  }
}
