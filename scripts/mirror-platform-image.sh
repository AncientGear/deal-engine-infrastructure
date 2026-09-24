#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage:
  mirror-platform-image.sh <image-key> <version>

Examples:
  mirror-platform-image.sh aws-load-balancer-controller v3.5.0

Supported image keys:
  aws-load-balancer-controller

Environment overrides:
  AWS_PROFILE              AWS profile to use. Default: ahau-2026
  AWS_REGION               AWS region for private ECR. Default: us-east-2
  AWS_ACCOUNT_ID           AWS account ID. Default: discovered with STS
  SOURCE_IMAGE             Override source image repository without tag
  TARGET_REPOSITORY        Override private ECR repository name
  CREATE_REPOSITORY        Create the ECR repository if missing. Default: false

Notes:
  Terraform should normally create the private ECR repository first. Set
  CREATE_REPOSITORY=true only for an emergency/manual bootstrap.
USAGE
}

if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
  usage
  exit 0
fi

if [ "$#" -ne 2 ]; then
  usage >&2
  exit 1
fi

image_key="$1"
version="$2"

aws_profile="${AWS_PROFILE:-ahau-2026}"
aws_region="${AWS_REGION:-${AWS_DEFAULT_REGION:-us-east-2}}"
create_repository="${CREATE_REPOSITORY:-false}"

case "$image_key" in
  aws-load-balancer-controller)
    default_source_image="public.ecr.aws/eks/aws-load-balancer-controller"
    default_target_repository="platform/aws-load-balancer-controller"
    ;;
  *)
    echo "Unsupported image key: ${image_key}" >&2
    echo "Add a mapping in $(basename "$0") before mirroring this image." >&2
    exit 1
    ;;
esac

source_image="${SOURCE_IMAGE:-$default_source_image}"
target_repository="${TARGET_REPOSITORY:-$default_target_repository}"

account_id="${AWS_ACCOUNT_ID:-$(aws sts get-caller-identity \
  --profile "$aws_profile" \
  --query Account \
  --output text)}"

private_registry="${account_id}.dkr.ecr.${aws_region}.amazonaws.com"
source_ref="${source_image}:${version}"
target_ref="${private_registry}/${target_repository}:${version}"

echo "Mirroring platform image"
echo "  source: ${source_ref}"
echo "  target: ${target_ref}"
echo "  profile: ${aws_profile}"
echo "  region:  ${aws_region}"

if ! aws ecr describe-repositories \
  --profile "$aws_profile" \
  --region "$aws_region" \
  --repository-names "$target_repository" >/dev/null 2>&1; then
  if [ "$create_repository" = "true" ]; then
    echo "Creating ECR repository: ${target_repository}"
    aws ecr create-repository \
      --profile "$aws_profile" \
      --region "$aws_region" \
      --repository-name "$target_repository" >/dev/null
  else
    echo "ECR repository does not exist: ${target_repository}" >&2
    echo "Apply the Terraform platform image repository first, or set CREATE_REPOSITORY=true." >&2
    exit 1
  fi
fi

aws ecr get-login-password \
  --profile "$aws_profile" \
  --region "$aws_region" \
  | docker login \
    --username AWS \
    --password-stdin "$private_registry" >/dev/null

docker pull "$source_ref"
docker tag "$source_ref" "$target_ref"
docker push "$target_ref"

echo "Mirror complete: ${target_ref}"
