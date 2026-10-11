#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "$0")/../.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/bin"
cp "$root/scripts/floci-bootstrap-state.sh" "$tmp/bootstrap.sh"
export CALLS="$tmp/calls"
cat > "$tmp/bin/aws" <<'MOCK'
#!/usr/bin/env bash
printf 'aws %s\n' "$*" >> "$CALLS"
case "$*" in
  *dynamodb*) echo 'unexpected DynamoDB call' >&2; exit 1 ;;
  *'sts get-caller-identity'*) [ "$SCENARIO" != unavailable ] ;;
  *'s3api head-bucket'*) [ "$SCENARIO" = existing ] ;;
  *'s3api create-bucket'*) [ "$SCENARIO" != create-failure ] ;;
  *) exit 1 ;;
esac
MOCK
cat > "$tmp/bin/sleep" <<'MOCK'
#!/usr/bin/env bash
printf 'sleep %s\n' "$*" >> "$CALLS"
MOCK
chmod +x "$tmp/bin/aws" "$tmp/bin/sleep"
export PATH="$tmp/bin:$PATH"
export AWS_ENDPOINT_URL=http://mock.invalid AWS_ACCESS_KEY_ID=test AWS_SECRET_ACCESS_KEY=test
export TG_STATE_BUCKET=test-state
fail() { echo "FAIL: $*" >&2; exit 1; }
run() {
  : > "$CALLS"
  SCENARIO="$1" AWS_DEFAULT_REGION="$2" bash "$tmp/bootstrap.sh" >"$tmp/out" 2>&1
}
for region in us-east-1 us-east-2; do
  for scenario in existing missing; do
    run "$scenario" "$region" || fail "$scenario/$region: $(<"$tmp/out")"
    ! grep -q dynamodb "$CALLS" || fail 'DynamoDB called'
    ! grep -q 'Terraform state backend is ready' "$tmp/out" || fail 'unsupported readiness claim'
    grep -q 'S3 state bucket is ready' "$tmp/out" || fail 'missing bucket readiness'
    grep -q 'S3 lock compatibility is unverified' "$tmp/out" || fail 'missing compatibility warning'
    grep -q 'stop.*lock.*fail' "$tmp/out" || fail 'missing stop-on-lock-failure warning'
    if [ "$scenario" = existing ]; then
      ! grep -q create-bucket "$CALLS" || fail 'existing bucket recreated'
    else
      grep -q 'create-bucket --bucket test-state' "$CALLS" || fail 'bucket not created'
      if [ "$region" = us-east-1 ]; then
        ! grep -q LocationConstraint "$CALLS" || fail 'us-east-1 constraint'
      else
        grep -q "LocationConstraint=$region" "$CALLS" || fail 'missing region constraint'
      fi
    fi
  done
done
if run unavailable us-east-2; then fail 'readiness failure accepted'; fi
[ "$(grep -c 'sts get-caller-identity' "$CALLS")" -eq 30 ] || fail 'readiness retry bound'
[ "$(grep -c '^sleep 1$' "$CALLS")" -eq 29 ] || fail 'sleep retry bound'
! grep -q 's3api\|dynamodb' "$CALLS" || fail 'continued after readiness failure'
grep -q 'did not become ready' "$tmp/out" || fail 'missing readiness error'
if run create-failure us-east-2; then fail 'bucket creation failure accepted'; fi
! grep -q 'is ready' "$tmp/out" || fail 'readiness reported after failure'
echo 'floci bootstrap offline tests passed'
