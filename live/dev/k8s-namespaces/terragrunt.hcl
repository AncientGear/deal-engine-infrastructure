terraform {
  source = "git@github.com:AncientGear/infrastructure-modules.git//aws/k8s-namespaces?ref=k8s-namespaces-v0.1.0"
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
  platform_namespace = "gateway-system"
  authorized_application_namespaces = [
    "backend-${include.env.locals.env}",
  ]
}

dependency "eks" {
  config_path = "../eks"

  mock_outputs = {
    eks_name = "${include.env.locals.env}-demo"
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
