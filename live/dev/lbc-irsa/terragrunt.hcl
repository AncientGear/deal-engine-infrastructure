terraform {
  source = "git@github.com:AncientGear/infrastructure-modules.git//aws/eks-irsa-aws-load-balancer-controller?ref=eks-irsa-aws-load-balancer-controller-v0.1.1"
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
  cluster_name      = dependency.eks.outputs.eks_name
  vpc_id            = dependency.vpc.outputs.vpc_id
  aws_region        = include.env.locals.region
  oidc_provider_arn = dependency.eks.outputs.oidc_provider_arn
  oidc_provider_url = dependency.eks.outputs.oidc_provider_url
  role_name         = "${include.env.locals.env}-${include.env.locals.project}-aws-load-balancer-controller"

  namespace            = "kube-system"
  service_account_name = "aws-load-balancer-controller"

  tags = {
    Environment = include.env.locals.env
    Project     = include.env.locals.project
    Maintainer  = "AncientGear"
    Name        = "${include.env.locals.env}-${include.env.locals.project}-aws-load-balancer-controller"
  }
}

dependency "eks" {
  config_path = "../eks"

  mock_outputs = {
    eks_name          = "${include.env.locals.env}-demo"
    oidc_provider_arn = "arn:aws:iam::123456789012:oidc-provider/oidc.eks.${include.env.locals.region}.amazonaws.com/id/EXAMPLED539D4633E53DE1B71EXAMPLE"
    oidc_provider_url = "https://oidc.eks.${include.env.locals.region}.amazonaws.com/id/EXAMPLED539D4633E53DE1B71EXAMPLE"
  }
}

dependency "vpc" {
  config_path = "../vpc"

  mock_outputs = {
    vpc_id = "vpc-12345678"
  }
}
