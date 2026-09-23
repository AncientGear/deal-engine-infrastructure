terraform {
  source = "git@github.com:AncientGear/infrastructure-modules.git//aws/eks?ref=eks-v0.1.1"
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

  node_groups = {
    general = {
      capacity_type  = "ON_DEMAND"
      instance_types = ["m5.xlarge"]

      labels = {
        workload = "prod"
      }

      taints = [
        {
          key    = "workload"
          value  = "prod"
          effect = "NO_SCHEDULE"
        }
      ]

      scaling_config = {
        desired_size = 2
        max_size     = 8
        min_size     = 2
      }
    }
  }
}

dependency "vpc" {
  config_path = "../vpc"

  mock_outputs = {
    private_app_subnet_ids = ["subnet-1234", "subnet-5678", "subnet-9012"]
  }
}