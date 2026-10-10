terraform {
  source = "git@github.com:AncientGear/infrastructure-modules.git//aws/external-secrets-operator?ref=external-secrets-operator-v0.1.0"
}

include "root" {
  path = find_in_parent_folders("root.hcl")
}

include "env" {
  path           = find_in_parent_folders("env.hcl")
  expose         = true
  merge_strategy = "no_merge"
}

dependency "eks" {
  config_path = "../eks"

  mock_outputs = {
    eks_name = "${include.env.locals.env}-demo"
  }
  mock_outputs_allowed_terraform_commands = ["validate"]
}

inputs = {
  cluster_name = dependency.eks.outputs.eks_name
  region       = include.env.locals.region
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
