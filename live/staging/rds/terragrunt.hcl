terraform {
  source = "git@github.com:AncientGear/infrastructure-modules.git//aws/rds?ref=rds-v0.0.2"
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
  allocated_storage    = 30
  db_name              = "my_db"
  engine               = "postgres"
  port                 = "5432"
  engine_version       = "15.3"
  instance_class       = "db.t4.large"
  username             = "${include.env.locals.env}_user"
  parameter_group_name = "default.postgres15.3"
  skip_final_snapshot  = true
  tags = {
    Name        = "my-rds-instance"
    Environment = "${include.env.locals.env}"
  }
  multi_az_enable       = false
  vpc_id                = dependency.vpc.outputs.vpc_id
  private_db_subnet_ids = dependency.vpc.outputs.private_db_subnet_ids
  allowed_cidr_blocks   = dependency.vpc.outputs.private_app_subnet_cidr_blocks
  env                   = include.env.locals.env
}

dependency "vpc" {
  config_path = "../vpc"

  mock_outputs = {
    vpc_id                         = "vpc-12345678"
    private_db_subnet_ids          = ["subnet-1234", "subnet-5678"]
    private_app_subnet_cidr_blocks = ["10.0.1.0/24", "10.0.2.0/24"]
  }
}
