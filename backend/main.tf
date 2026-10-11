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
