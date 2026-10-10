terraform {
  source = "git@github.com:AncientGear/infrastructure-modules.git//aws/backend-runtime-secrets?ref=backend-runtime-secrets-v0.1.0"
}

include "root" {
  path = find_in_parent_folders("root.hcl")
}

include "env" {
  path           = find_in_parent_folders("env.hcl")
  expose         = true
  merge_strategy = "no_merge"
}

# Ordering only: namespace and ESO CRDs must exist before this release.
# ESO's separate release is pinned to 2.11.0 and owns the v1 CRDs.
dependencies {
  paths = ["../k8s-namespaces", "../external-secrets-operator"]
}

dependency "eks" {
  config_path = "../eks"
  mock_outputs = {
    eks_name          = "${include.env.locals.env}-demo"
    oidc_provider_arn = "arn:aws:iam::989200477899:oidc-provider/oidc.eks.us-east-2.amazonaws.com/id/EXAMPLE"
    oidc_provider_url = "https://oidc.eks.us-east-2.amazonaws.com/id/EXAMPLE"
  }
  mock_outputs_allowed_terraform_commands = ["validate"]
}

inputs = {
  cluster_name      = dependency.eks.outputs.eks_name
  oidc_provider_arn = dependency.eks.outputs.oidc_provider_arn
  oidc_provider_url = dependency.eks.outputs.oidc_provider_url
  region            = include.env.locals.region
  account_id        = include.env.locals.account_id
  namespace         = "backend-dev"
  role_name         = "dev-dealengine-backend-runtime-secrets"
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
