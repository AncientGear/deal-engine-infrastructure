terraform {
  source = "git@github.com:AncientGear/infrastructure-modules.git//aws/cloudfront?ref=cloudfront-v0.1.1"
}

include "root" {
  path = find_in_parent_folders("root.hcl")
}

include "env" {
  path           = find_in_parent_folders("env.hcl")
  expose         = true
  merge_strategy = "no_merge"
}

dependency "frontend_bucket" {
  config_path = "../s3-cloudfront"
}

dependency "frontend_certificate" {
  config_path = "../frontend-certificate"
}

inputs = {
  bucket_id                   = dependency.frontend_bucket.outputs.bucket_name
  bucket_arn                  = dependency.frontend_bucket.outputs.bucket_arn
  bucket_regional_domain_name = dependency.frontend_bucket.outputs.bucket_regional_domain_name

  cloudfront_origin_access_control_id = "dealengine-dev-frontend-oac"
  frontend_release_id                 = "38348691723-1"
  frontend_origin_mode                = "current"

  # Existing controller-managed ALB; refresh this binding if it is recreated.
  alb_origin_arn         = "arn:aws:elasticloadbalancing:us-east-2:989200477899:loadbalancer/app/k8s-gateways-gatewayd-6252289d02/b38919fd1786fc8e"
  alb_origin_domain_name = "api.alb-dev-dealengine.saul-tzakum.tech"
  vpc_origin_name        = "dealengine-dev-backend"

  acm_certificate_arn = dependency.frontend_certificate.outputs.certificate_arn
  aliases             = ["dev-dealengine.saul-tzakum.tech"]
  price_class         = "PriceClass_100"

  tags = {
    Environment = include.env.locals.env
    Project     = include.env.locals.project
    Maintainer  = "AncientGear"
  }
}