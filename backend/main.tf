resource "aws_s3_bucket" "example" {
  bucket = "dealengine-demo-tf-eks-state-bucket"

  lifecycle {
    prevent_destroy = false
  }

  tags = {
    Name        = "My bucket"
    Environment = "Dev"
  }
}

resource "aws_dynamodb_table" "basic-dynamodb-table" {
  name           = "dealengine-eks-state-locking-table"
  billing_mode   = "PROVISIONED"
  hash_key       = "LockID"
  read_capacity  = 20
  write_capacity = 20

  attribute {
    name = "LockID"
    type = "S"
  }

  tags = {
    Name        = "dealengine-dynamodb-table-1"
    Environment = "production"
  }
}