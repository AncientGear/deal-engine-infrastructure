# S3 native state locking requires Terraform 1.10 or newer.
terraform_version_constraint = ">= 1.10.0"

locals {
  aws_region   = read_terragrunt_config(find_in_parent_folders("env.hcl")).locals.region
  state_region = get_env("TG_STATE_REGION", "us-east-2")
  state_bucket = get_env("TG_STATE_BUCKET", "dealengine-demo-tf-eks-state-bucket")

  unit_region_file = "${get_terragrunt_dir()}/region.hcl"
  provider_region  = fileexists(local.unit_region_file) ? read_terragrunt_config(local.unit_region_file).locals.region : local.aws_region
}

remote_state {
  backend = "s3"
  generate = {
    path      = "state.tf"
    if_exists = "overwrite_terragrunt"
  }

  config = {
    bucket = local.state_bucket

    key          = "${path_relative_to_include()}/terraform.tfstate"
    region       = local.state_region
    encrypt      = true
    use_lockfile = true
  }
}

generate "provider" {
  path      = "terragrunt-provider.tf"
  if_exists = "overwrite_terragrunt"

  contents = <<EOF
provider "aws" {
  region = "${local.provider_region}"
}
EOF
}