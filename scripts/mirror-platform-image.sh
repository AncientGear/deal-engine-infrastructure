#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage:
  mirror-platform-image.sh [--platform linux/amd64|linux/arm64] [--source-tag tag] <image-key> <version>

Examples:
  mirror-platform-image.sh aws-load-balancer-controller v3.5.0
  mirror-platform-image.sh --source-tag v3.5.0 --platform linux/arm64 aws-load-balancer-controller v3.5.0-arm64

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

platform="linux/amd64"
source_tag=""
source_tag_set=false
while [ "$#" -gt 0 ]; do
  case "$1" in
    --platform|--source-tag)
      option="$1"
      if [ "$#" -lt 2 ] || [ -z "$2" ] || [[ "$2" == --* ]]; then
        echo "Missing value for ${option}" >&2
        exit 1
      fi
      if [ "$option" = "--platform" ]; then platform="$2"; else source_tag="$2"; source_tag_set=true; fi
      shift 2
      ;;
    --*) echo "Unknown option: $1" >&2; exit 1 ;;
    *) break ;;
  esac
done
case "$platform" in
  linux/amd64|linux/arm64) ;;
  *) echo "Unsupported platform: ${platform}" >&2; exit 1 ;;
esac

if [ "$#" -ne 2 ]; then
  usage >&2
  exit 1
fi

image_key="$1"
version="$2"
if [ "$source_tag_set" = false ]; then source_tag="$version"; fi
if [ -z "$source_tag" ] || [ -z "$version" ]; then
  echo "Source tag and target version must be nonempty" >&2
  exit 1
fi
case "$image_key" in
  --*) echo "Unknown option: $image_key" >&2; exit 1 ;;
esac
case "$version" in
  --*) echo "Unknown option: $version" >&2; exit 1 ;;
esac

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
source_ref="${source_image}:${source_tag}"
target_ref="${private_registry}/${target_repository}:${version}"

echo "Mirroring platform image"
echo "  source: ${source_ref}"
echo "  target: ${target_ref}"
echo "  profile: ${aws_profile}"
echo "  region:  ${aws_region}"
echo "  platform: ${platform}"

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

docker pull --platform "$platform" "$source_ref"
architecture="$(docker inspect --format '{{.Architecture}}' "$source_ref")"
if [ "$architecture" != "${platform#linux/}" ]; then
  echo "Pulled image architecture ${architecture} does not match ${platform}; refusing to push." >&2
  exit 1
fi
docker tag "$source_ref" "$target_ref"
docker push "$target_ref"

echo "Mirror complete: ${target_ref}"
