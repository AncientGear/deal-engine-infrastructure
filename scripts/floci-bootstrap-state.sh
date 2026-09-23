#!/usr/bin/env bash
set -euo pipefail

AWS_ENDPOINT_URL="${AWS_ENDPOINT_URL:-http://localhost:4566}"
AWS_DEFAULT_REGION="${AWS_DEFAULT_REGION:-us-east-2}"
AWS_ACCESS_KEY_ID="${AWS_ACCESS_KEY_ID:-test}"
AWS_SECRET_ACCESS_KEY="${AWS_SECRET_ACCESS_KEY:-test}"
TG_STATE_BUCKET="${TG_STATE_BUCKET:-dealengine-demo-tf-eks-state-bucket}"
TG_LOCK_TABLE="${TG_LOCK_TABLE:-dealengine-eks-state-locking-table}"

export AWS_ENDPOINT_URL AWS_DEFAULT_REGION AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY

aws_local() {
  aws --endpoint-url "$AWS_ENDPOINT_URL" --region "$AWS_DEFAULT_REGION" "$@"
}

echo "Waiting for Floci at ${AWS_ENDPOINT_URL}..."
for attempt in $(seq 1 30); do
  if aws_local sts get-caller-identity >/dev/null 2>&1; then
    break
  fi

  if [ "$attempt" -eq 30 ]; then
    echo "Floci did not become ready at ${AWS_ENDPOINT_URL}" >&2
    exit 1
  fi

  sleep 1
done

if aws_local s3api head-bucket --bucket "$TG_STATE_BUCKET" >/dev/null 2>&1; then
  echo "S3 state bucket already exists: ${TG_STATE_BUCKET}"
else
  echo "Creating S3 state bucket: ${TG_STATE_BUCKET}"
  if [ "$AWS_DEFAULT_REGION" = "us-east-1" ]; then
    aws_local s3api create-bucket --bucket "$TG_STATE_BUCKET" >/dev/null
  else
    aws_local s3api create-bucket \
      --bucket "$TG_STATE_BUCKET" \
      --create-bucket-configuration "LocationConstraint=${AWS_DEFAULT_REGION}" >/dev/null
  fi
fi

if aws_local dynamodb describe-table --table-name "$TG_LOCK_TABLE" >/dev/null 2>&1; then
  echo "DynamoDB lock table already exists: ${TG_LOCK_TABLE}"
else
  echo "Creating DynamoDB lock table: ${TG_LOCK_TABLE}"
  aws_local dynamodb create-table \
    --table-name "$TG_LOCK_TABLE" \
    --billing-mode PAY_PER_REQUEST \
    --attribute-definitions AttributeName=LockID,AttributeType=S \
    --key-schema AttributeName=LockID,KeyType=HASH >/dev/null
fi

echo "Floci Terraform state backend is ready."
