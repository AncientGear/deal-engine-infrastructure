#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "$0")/../.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
fixture="$tmp/repo"
mkdir -p "$tmp/bin" "$fixture/scripts"
cp "$root/scripts/destroy-env.sh" "$root/scripts/destroy-dev.sh" "$fixture/scripts/"
for env in dev staging prod; do
  for unit in k8s-gateway k8s-namespaces alb-certificate eks-addons lbc-irsa eks rds network-services s3-cloudfront frontend-certificate ecr vpc; do
    mkdir -p "$fixture/live/$env/$unit"
    : > "$fixture/live/$env/$unit/terragrunt.hcl"
  done
done
root="$fixture"
export CALLS="$tmp/calls"
: > "$CALLS"
cat > "$tmp/bin/aws" <<'MOCK'
#!/usr/bin/env bash
printf 'aws %s\n' "$*" >> "$CALLS"
case "$*" in
  *get-caller-identity*Account*) echo "${MOCK_ACCOUNT:-989200477899}" ;;
  *get-caller-identity*Arn*) echo arn:aws:iam::989200477899:user/test ;;
  *list-images*) python3 -c 'import json; print(json.dumps([{"imageDigest": "sha256:%064x" % i} for i in range(205)]))' ;;
  *batch-delete-image*) if [ "${MOCK_DELETE_FAIL:-0}" = 1 ]; then echo 'failed' >&2; exit 1; fi; echo '{"failures":[]}' ;;
  *describe-repositories*) if [ "${MOCK_DESCRIBE_FAIL:-0}" = 1 ]; then echo AccessDeniedException >&2; exit 1; fi ;;
esac
MOCK
cat > "$tmp/bin/terragrunt" <<'MOCK'
#!/usr/bin/env bash
printf 'terragrunt %s %s\n' "${PWD##*/}" "$*" >> "$CALLS"
MOCK
chmod +x "$tmp/bin/aws" "$tmp/bin/terragrunt"
export PATH="$tmp/bin:$PATH"
fail() { echo "FAIL: $*" >&2; exit 1; }
if bash "$root/scripts/destroy-dev.sh" --confirm destroy-dev --profile >/dev/null 2>&1; then fail 'missing option accepted'; fi
if bash "$root/scripts/destroy-dev.sh" --confirm destroy-dev --auto-approve >"$tmp/out" 2>&1; then fail 'missing consent accepted'; fi
[ ! -s "$CALLS" ] || fail 'missing consent made calls'
[ ! -s "$CALLS" ] || fail 'missing option made calls'
MOCK_ACCOUNT=111 bash "$root/scripts/destroy-dev.sh" --confirm destroy-dev --delete-namespaces --auto-approve >"$tmp/out" 2>&1 && fail 'wrong account accepted'
! grep -q 'terragrunt\|batch-delete-image' "$CALLS" || fail 'wrong account mutated'
: > "$CALLS"
bash "$root/scripts/destroy-dev.sh" --confirm destroy-dev --delete-namespaces --auto-approve >"$tmp/out" 2>&1 || fail "normal run failed: $(<"$tmp/out")"
! grep -q 'platform/aws-load-balancer-controller\|platform-images' "$CALLS" || fail 'shared repository touched'
for unit in k8s-gateway k8s-namespaces alb-certificate eks-addons lbc-irsa eks rds network-services s3-cloudfront frontend-certificate ecr vpc; do grep -q "terragrunt $unit destroy" "$CALLS" || fail "missing $unit"; done
[ "$(grep -c 'aws ecr batch-delete-image' "$CALLS")" -eq 3 ] || fail 'batch limit not handled'
line() { grep -n "terragrunt $1 destroy" "$CALLS" | head -1 | cut -d: -f1; }
[ "$(line k8s-gateway)" -lt "$(line k8s-namespaces)" ] && [ "$(line k8s-namespaces)" -lt "$(line eks-addons)" ] && [ "$(line eks-addons)" -lt "$(line eks)" ] && [ "$(line eks)" -lt "$(line network-services)" ] && [ "$(line s3-cloudfront)" -lt "$(line frontend-certificate)" ] && [ "$(line frontend-certificate)" -lt "$(line vpc)" ] || fail 'wrong order'
: > "$CALLS"
MOCK_DESCRIBE_FAIL=1 bash "$root/scripts/destroy-dev.sh" --confirm destroy-dev --delete-namespaces --auto-approve >"$tmp/out" 2>&1 && fail 'access denied ignored'
: > "$CALLS"
MOCK_DELETE_FAIL=1 bash "$root/scripts/destroy-dev.sh" --confirm destroy-dev --delete-namespaces --auto-approve >"$tmp/out" 2>&1 && fail 'batch failure ignored'
echo 'destroy-dev offline tests passed'
