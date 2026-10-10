#!/usr/bin/env bash
set -euo pipefail
script="$(cd "$(dirname "$0")/.." && pwd)/mirror-platform-image.sh"
# Local function mocks propagate into the script via exported functions.
aws() { printf 'aws %s\n' "$*" >>"$LOG"; if [[ " $* " == *' get-login-password '* ]]; then printf 'password\n'; fi; }
docker() {
  printf 'docker %s\n' "$*" >>"$LOG"
  if [[ "$1" == inspect ]]; then printf '%s\n' "$INSPECT_ARCH"; fi
}
export -f aws docker
LOG="$(mktemp)"
trap 'unlink "$LOG"' EXIT
export LOG AWS_ACCOUNT_ID=123456789012 AWS_REGION=us-east-2 INSPECT_ARCH=arm64
source_ref=public.ecr.aws/eks/aws-load-balancer-controller:v3.5.0
target_ref=123456789012.dkr.ecr.us-east-2.amazonaws.com/platform/aws-load-balancer-controller:v3.5.0-arm64
: >"$LOG"
bash "$script" --source-tag v3.5.0 --platform linux/arm64 aws-load-balancer-controller v3.5.0-arm64 >/dev/null
grep -Fxq "docker pull --platform linux/arm64 $source_ref" "$LOG"
grep -Fxq "docker tag $source_ref $target_ref" "$LOG"
grep -Fxq "docker push $target_ref" "$LOG"
: >"$LOG"
INSPECT_ARCH=amd64 bash "$script" aws-load-balancer-controller v3.5.0 >/dev/null
grep -Fxq "docker pull --platform linux/amd64 $source_ref" "$LOG"
grep -Fxq "docker push 123456789012.dkr.ecr.us-east-2.amazonaws.com/platform/aws-load-balancer-controller:v3.5.0" "$LOG"
: >"$LOG"
INSPECT_ARCH=amd64 bash "$script" --source-tag v3.5.0 --platform linux/arm64 aws-load-balancer-controller v3.5.0-arm64 >/dev/null 2>&1 && { echo 'mismatch accepted' >&2; exit 1; }
! grep -q '^docker tag ' "$LOG"
! grep -q '^docker push ' "$LOG"
for args in '--source-tag "" aws-load-balancer-controller v3.5.0-arm64' '--bogus aws-load-balancer-controller v3.5.0' '--platform linux/other aws-load-balancer-controller v3.5.0'; do
  : >"$LOG"
  eval "bash \"\$script\" $args >/dev/null 2>&1" && { echo "invalid input accepted: $args" >&2; exit 1; }
  ! grep -q '^aws ' "$LOG"
done
echo 'offline mirror tests passed'
