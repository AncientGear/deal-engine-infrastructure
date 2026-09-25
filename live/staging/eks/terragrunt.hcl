terraform {
  source = "git@github.com:AncientGear/infrastructure-modules.git//aws/eks?ref=eks-v0.1.3"
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

  coredns = {
    enabled                   = true
    addon_version             = "v1.14.6-eksbuild.4"
    replica_count             = 2
    workload_toleration_value = "shared"
    corefile                  = <<-EOT
.:53 {
    errors
    health {
        lameduck 5s
    }
    ready
    kubernetes cluster.local in-addr.arpa ip6.arpa {
        pods insecure
        fallthrough in-addr.arpa ip6.arpa
    }
    prometheus :9153
    forward . /etc/resolv.conf
    cache 30
    loop
    reload
    loadbalance
}
EOT
  }

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
        desired_size = 2
        max_size     = 4
        min_size     = 1
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