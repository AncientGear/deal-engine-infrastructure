terraform {
  source = "git@github.com:AncientGear/infrastructure-modules.git//aws/k8s-addons?ref=k8s-addons-v0.1.2"
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
  cluster_name = dependency.eks.outputs.eks_name
  region       = include.env.locals.region
  vpc_id       = dependency.vpc.outputs.vpc_id

  aws_load_balancer_controller = {
    enabled              = true
    role_arn             = dependency.lbc_irsa.outputs.role_arn
    namespace            = dependency.lbc_irsa.outputs.namespace
    service_account_name = dependency.lbc_irsa.outputs.service_account_name
    image_repository     = "${include.env.locals.account_id}.dkr.ecr.${include.env.locals.region}.amazonaws.com/platform/aws-load-balancer-controller"

    node_selector = {
      workload = "shared"
    }

    tolerations = [
      {
        key      = "workload"
        operator = "Equal"
        value    = "shared"
        effect   = "NoSchedule"
      }
    ]
  }
}

dependency "eks" {
  config_path = "../eks"

  mock_outputs = {
    eks_name = "${include.env.locals.env}-demo"
  }
}

dependency "vpc" {
  config_path = "../vpc"

  mock_outputs = {
    vpc_id = "vpc-12345678"
  }
}

dependency "lbc_irsa" {
  config_path = "../lbc-irsa"

  mock_outputs = {
    role_arn             = "arn:aws:iam::123456789012:role/example-aws-load-balancer-controller"
    namespace            = "kube-system"
    service_account_name = "aws-load-balancer-controller"
  }
}

generate "helm_provider" {
  path      = "helm-provider.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<EOF

data "aws_eks_cluster" "eks" {
  name = var.cluster_name
}

data "aws_eks_cluster_auth" "eks" {
  name = var.cluster_name
}

provider "helm" {
  kubernetes = {
    host                   = data.aws_eks_cluster.eks.endpoint
    cluster_ca_certificate = base64decode(data.aws_eks_cluster.eks.certificate_authority[0].data)
    token                  = data.aws_eks_cluster_auth.eks.token
  }
}
EOF
}
