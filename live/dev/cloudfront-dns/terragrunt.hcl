terraform {
  source = "git@github.com:AncientGear/infrastructure-modules.git//aws/cloudfront-dns?ref=cloudfront-dns-v0.1.0"
}

include "root" {
  path = find_in_parent_folders("root.hcl")
}

dependency "cloudfront" {
  config_path = "../cloudfront"
}

inputs = {
  cloudflare_zone_id       = "e9de4cd1676a312ab2397d27977d00ab"
  frontend_domain_name     = "dev-dealengine.saul-tzakum.tech"
  distribution_domain_name = dependency.cloudfront.outputs.distribution_domain_name
}