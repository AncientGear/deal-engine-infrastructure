terraform {
  source = "git@github.com:AncientGear/infrastructure-modules.git//aws/network-services?ref=network-services-v0.0.4"
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
  interface_endpoints = [
    {
      service_name = "com.amazonaws.${include.env.locals.region}.ecr.api"
      subnet_ids   = dependency.vpc.outputs.private_app_subnet_ids
      private_dns  = false
    },
    {
      service_name = "com.amazonaws.${include.env.locals.region}.ecr.dkr"
      subnet_ids   = dependency.vpc.outputs.private_app_subnet_ids
      private_dns  = false
    },
    {
      service_name = "com.amazonaws.${include.env.locals.region}.sts"
      subnet_ids   = dependency.vpc.outputs.private_app_subnet_ids
      private_dns  = false
    },
    {
      service_name = "com.amazonaws.${include.env.locals.region}.secretsmanager"
      subnet_ids   = dependency.vpc.outputs.private_app_subnet_ids
      private_dns  = false
    }
  ]

  interface_endpoint_tags = {
    "Name" = "${include.env.locals.env}-network-services-interface-endpoint"
  }

  gateway_endpoints = [
    {
      service_name    = "com.amazonaws.${include.env.locals.region}.s3"
      route_table_ids = dependency.vpc.outputs.private_route_table_ids
      policy_json     = null
    }
  ]

  gateway_endpoint_tags = {
    "Name" = "${include.env.locals.env}-network-services-gateway-endpoint"
  }

  vpc_id      = dependency.vpc.outputs.vpc_id
  cidr_blocks = dependency.vpc.outputs.private_app_subnet_cidr_blocks
  subnet_tags = {
    "Name" = "${include.env.locals.env}-network-services-sg"
  }
}

dependency "vpc" {
  config_path = "../vpc"

  mock_outputs = {
    private_app_subnet_ids         = ["subnet-1234", "subnet-5678"]
    private_route_table_ids        = ["rtb-1234", "rtb-5678", "rtb-9012"]
    vpc_id                         = "vpc-1234"
    private_app_subnet_cidr_blocks = ["10.0.1.0/24", "10.0.2.0/24"]
  }
}
