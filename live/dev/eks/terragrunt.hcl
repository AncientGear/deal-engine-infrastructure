terraform {
  source = "git@github.com:AncientGear/infrastructure-modules.git//aws/eks?ref=eks-v0.1.2"
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
  eks_version = "1.35"
  env         = include.env.locals.env
  eks_name    = "demo"
  subnet_ids  = dependency.vpc.outputs.private_app_subnet_ids

  endpoint_private_access = true
  endpoint_public_access  = true

  node_groups = {
    general = {
      capacity_type  = "ON_DEMAND"
      instance_types = ["t3.small"]

      labels = {
        workload = "shared"
      }

      taints = [
        {
          key    = "workload"
          value  = "shared"
          effect = "NO_SCHEDULE"
        }
      ]

      scaling_config = {
        desired_size = 1
        max_size     = 2
        min_size     = 0
      }
    }
  }
}

dependency "vpc" {
  config_path = "../vpc"

  mock_outputs = {
    private_app_subnet_ids = ["subnet-1234", "subnet-5678"]
  }
}