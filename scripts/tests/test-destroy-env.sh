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
  *batch-delete-image*) python3 - "$@" <<'PY'
import json,os,sys
ids=json.loads(sys.argv[sys.argv.index('--image-ids')+1])
assert 0 < len(ids) <= 100, len(ids)
print(json.dumps({'failures':[{'imageId':ids[0]}] if os.getenv('MOCK_PARTIAL_FAIL') else []}))
PY
    ;;
  *describe-repositories*) : ;;
esac
MOCK
cat > "$tmp/bin/terragrunt" <<'MOCK'
#!/usr/bin/env bash
printf 'terragrunt %s %s\n' "$PWD" "$*" >> "$CALLS"
MOCK
chmod +x "$tmp/bin/aws" "$tmp/bin/terragrunt"
export PATH="$tmp/bin:$PATH"
fail() { echo "FAIL: $*" >&2; exit 1; }
reject() {
  : > "$CALLS"
  if bash "$root/scripts/$1" "${@:2}" >"$tmp/out" 2>&1; then fail "accepted: $*"; fi
  [ ! -s "$CALLS" ] || fail "invalid input made calls: $*"
}
reject destroy-env.sh
reject destroy-env.sh --env all --confirm destroy-all
reject destroy-env.sh --env prod --confirm destroy-dev
reject destroy-env.sh --env dev --env prod --confirm destroy-prod
reject destroy-env.sh --env dev --confirm destroy-dev --confirm destroy-prod
reject destroy-env.sh --env dev --confirm destroy-dev --expected-account 111
reject destroy-dev.sh --env prod --confirm destroy-dev
reject destroy-dev.sh --env=prod --confirm destroy-dev
for env in dev staging prod; do
  reject destroy-env.sh --env "$env" --confirm "destroy-$env"
  grep -q 'EKS destroys namespaces' "$tmp/out" || fail 'missing namespace warning'
  reject destroy-env.sh --env "$env" --confirm "destroy-$env" --auto-approve
done
for env in dev staging prod; do
  : > "$root/live/$env/k8s-namespaces/terragrunt.hcl"
  # The selected unit must exist before any cloud command.
  mv "$root/live/$env/k8s-namespaces/terragrunt.hcl" "$tmp/$env.hcl"
  reject destroy-env.sh --env "$env" --confirm "destroy-$env" --delete-namespaces --auto-approve
  mv "$tmp/$env.hcl" "$root/live/$env/k8s-namespaces/terragrunt.hcl"
done
for env in dev staging prod; do
  : > "$CALLS"
  bash "$root/scripts/destroy-env.sh" --env "$env" --confirm "destroy-$env" --delete-namespaces --auto-approve >"$tmp/out" 2>&1 || fail "$env: $(<"$tmp/out")"
  mapfile -t units < <(grep 'terragrunt .* destroy ' "$CALLS" | awk '{print $2}' | sed "s|$root/||")
  expected=(k8s-gateway k8s-namespaces alb-certificate eks-addons lbc-irsa eks rds network-services s3-cloudfront frontend-certificate ecr vpc)
  [ "${#units[@]}" -eq 12 ] || fail "$env unit count"
  for i in "${!expected[@]}"; do [ "${units[$i]}" = "live/$env/${expected[$i]}" ] || fail "$env order: ${units[$i]}"; done
  grep -q "repository-name $env-dealengine-ecr-repo" "$CALLS" || fail "$env ecr name"
  [ "$(grep -c 'aws ecr batch-delete-image' "$CALLS")" -eq 3 ] || fail "$env batch count"
done
: > "$CALLS"
bash "$root/scripts/destroy-dev.sh" --confirm destroy-dev --delete-namespaces --auto-approve >"$tmp/out" 2>&1 || fail "dev wrapper: $(<"$tmp/out")"
grep -q 'live/dev/vpc destroy' "$CALLS" || fail 'dev wrapper missing vpc'
: > "$CALLS"
MOCK_ACCOUNT=111 bash "$root/scripts/destroy-env.sh" --env prod --confirm destroy-prod --delete-namespaces --auto-approve >"$tmp/out" 2>&1 && fail 'account mismatch accepted'
! grep -q 'terragrunt\|batch-delete-image' "$CALLS" || fail 'account mismatch destructive calls'
: > "$CALLS"
MOCK_PARTIAL_FAIL=1 bash "$root/scripts/destroy-env.sh" --env dev --confirm destroy-dev --delete-namespaces --auto-approve >"$tmp/out" 2>&1 && fail 'partial ECR failure accepted'
! grep -q 'live/dev/ecr destroy\|live/dev/vpc destroy' "$CALLS" || fail 'continued after ECR failure'
echo 'destroy-env offline tests passed'
