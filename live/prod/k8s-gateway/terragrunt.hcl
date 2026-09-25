terraform {
  source = "git@github.com:AncientGear/infrastructure-modules.git//aws/k8s-gateway?ref=k8s-gateway-v0.1.1"
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
  platform_namespace               = "gateway-system"
  gateway_class_name               = "alb"
  gateway_name                     = "gateway-${include.env.locals.env}"
  load_balancer_configuration_name = "gateway-${include.env.locals.env}-alb"
  hostname                         = "*.alb-prod-dealengine.saul-tzakum.tech"
  regional_acm_certificate_arn     = dependency.alb_certificate.outputs.certificate_arn
  private_subnet_ids               = dependency.vpc.outputs.private_app_subnet_ids
  authorized_application_namespaces = [
    "backend-prod",
  ]

  alb_tags = {
    Environment = include.env.locals.env
    Project     = include.env.locals.project
    Maintainer  = "AncientGear"
    Name        = "${include.env.locals.env}-${include.env.locals.project}-gateway"
  }
}

dependency "eks" {
  config_path = "../eks"

  mock_outputs = {
    eks_name = "${include.env.locals.env}-demo"
  }
}

dependency "eks_addons" {
  config_path = "../eks-addons"

  mock_outputs = {
    aws_load_balancer_controller = {
      enabled              = true
      release_name         = "aws-load-balancer-controller"
      namespace            = "kube-system"
      service_account_name = "aws-load-balancer-controller"
    }
  }
}

dependency "alb_certificate" {
  config_path = "../alb-certificate"

  mock_outputs = {
    certificate_arn = "arn:aws:acm:${include.env.locals.region}:123456789012:certificate/12345678-1234-1234-1234-123456789012"
  }
}

dependency "vpc" {
  config_path = "../vpc"

  mock_outputs = {
    private_app_subnet_ids = ["subnet-1234abcd", "subnet-5678efab"]
  }
}

generate "kubernetes_provider" {
  path      = "kubernetes-provider.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<EOF

data "aws_eks_cluster" "eks" {
  name = "${dependency.eks.outputs.eks_name}"
}

data "aws_eks_cluster_auth" "eks" {
  name = "${dependency.eks.outputs.eks_name}"
}

provider "kubernetes" {
  host                   = data.aws_eks_cluster.eks.endpoint
  cluster_ca_certificate = base64decode(data.aws_eks_cluster.eks.certificate_authority[0].data)
  token                  = data.aws_eks_cluster_auth.eks.token
}
EOF
}
