#!/usr/bin/env bash
# Bootstrap Gateway API and AWS Load Balancer Controller Gateway CRDs outside Terraform state.

set -euo pipefail

readonly GATEWAY_API_VERSION="v1.6.0"
readonly GATEWAY_API_URL="https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.6.0/standard-install.yaml"
readonly GATEWAY_API_SHA256="a557172e8348f758479e9ee4000bbbb4b4aa48302a6b73461823ea5349bad56d"

readonly AWS_LBC_VERSION="v3.5.0"
readonly AWS_LBC_URL="https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/v3.5.0/config/crd/gateway/gateway-crds.yaml"
readonly AWS_LBC_SHA256="fce68bbfc74b4ed7dbea675f46981cbef1fffc8981cf19c0c1e7a2e9d6464862"

readonly FIELD_MANAGER="deal-engine-gateway-crd-bootstrap"
readonly ESTABLISH_TIMEOUT="120s"

readonly -a EXPECTED_CRDS=(
  "backendtlspolicies.gateway.networking.k8s.io"
  "gatewayclasses.gateway.networking.k8s.io"
  "gateways.gateway.networking.k8s.io"
  "grpcroutes.gateway.networking.k8s.io"
  "httproutes.gateway.networking.k8s.io"
  "listenersets.gateway.networking.k8s.io"
  "referencegrants.gateway.networking.k8s.io"
  "tcproutes.gateway.networking.k8s.io"
  "tlsroutes.gateway.networking.k8s.io"
  "udproutes.gateway.networking.k8s.io"
  "listenerruleconfigurations.gateway.k8s.aws"
  "loadbalancerconfigurations.gateway.k8s.aws"
  "targetgroupconfigurations.gateway.k8s.aws"
)

usage() {
  cat <<'EOF'
Usage:
  gateway-crds.sh diff --context CONTEXT
  gateway-crds.sh apply --context CONTEXT

Downloads and verifies the pinned Gateway API and AWS Load Balancer Controller
Gateway CRD bundles. "diff" only inspects the selected context; "apply" uses
server-side apply and waits for every expected CRD to become Established.

The Kubernetes context is required. This script never uses the current context
implicitly and has no delete or uninstall mode.
EOF
}

fail() {
  printf 'Error: %s\n' "$*" >&2
  exit 1
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || fail "required command not found: $1"
}

download() {
  local url="$1"
  local destination="$2"

  curl --fail --location --silent --show-error \
    --retry 3 --retry-delay 1 --retry-all-errors \
    --output "$destination" "$url"
}

verify_checksum() {
  local expected="$1"
  local file="$2"

  printf '%s  %s\n' "$expected" "$file" | sha256sum --check --status \
    || fail "checksum verification failed for $file"
}

mode="${1:-}"
if [[ "$mode" == "-h" || "$mode" == "--help" || -z "$mode" ]]; then
  usage
  exit 0
fi

case "$mode" in
  diff | apply) ;;
  *)
    usage >&2
    fail "mode must be 'diff' or 'apply'"
    ;;
esac
shift

if [[ "${1:-}" != "--context" || -z "${2:-}" || $# -ne 2 ]]; then
  usage >&2
  fail "an explicit Kubernetes context is required: --context CONTEXT"
fi
context="$2"

require_command curl
require_command kubectl
require_command sha256sum

tmp_dir="$(mktemp -d)"
cleanup() {
  rm -rf -- "$tmp_dir"
}
trap cleanup EXIT

gateway_bundle="$tmp_dir/gateway-api-standard-install.yaml"
aws_lbc_bundle="$tmp_dir/aws-lbc-gateway-crds.yaml"

printf 'Downloading Gateway API %s CRDs...\n' "$GATEWAY_API_VERSION"
download "$GATEWAY_API_URL" "$gateway_bundle"
printf 'Downloading AWS Load Balancer Controller %s Gateway CRDs...\n' "$AWS_LBC_VERSION"
download "$AWS_LBC_URL" "$aws_lbc_bundle"

verify_checksum "$GATEWAY_API_SHA256" "$gateway_bundle"
verify_checksum "$AWS_LBC_SHA256" "$aws_lbc_bundle"
printf 'Both bundle checksums verified.\n'

if [[ "$mode" == "diff" ]]; then
  set +e
  kubectl --context "$context" diff --server-side \
    --field-manager="$FIELD_MANAGER" -f "$gateway_bundle" -f "$aws_lbc_bundle"
  diff_status=$?
  set -e

  case "$diff_status" in
    0)
      printf 'No differences found for context %q.\n' "$context"
      ;;
    1)
      printf 'Differences found for context %q.\n' "$context"
      exit 1
      ;;
    *)
      fail "kubectl diff failed for context $context (exit status $diff_status)"
      ;;
  esac
  exit 0
fi

kubectl --context "$context" apply --server-side \
  --field-manager="$FIELD_MANAGER" -f "$gateway_bundle" -f "$aws_lbc_bundle"

for crd in "${EXPECTED_CRDS[@]}"; do
  kubectl --context "$context" wait --for=condition=Established \
    --timeout="$ESTABLISH_TIMEOUT" "crd/$crd"
done

printf 'Gateway CRDs are Established in context %q.\n' "$context"
