#!/usr/bin/env bash
# Offline executable-boundary tests; never run against a live unit.
set -euo pipefail
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
terragrunt=$(command -v terragrunt) || { echo 'Terragrunt is required' >&2; exit 1; }
fixture=$(mktemp -d /tmp/deal-engine-s3-locking.XXXXXX)
cleanup() {
  case "$fixture" in
    /tmp/deal-engine-s3-locking.??????) [[ -d "$fixture" ]] && rm -rf -- "$fixture" ;;
  esac
}
trap cleanup EXIT
mkdir -p "$fixture/unit" "$fixture/bin" "$fixture/alternate" "$fixture/home"
# Extract only the executable constraint: never copy backend/provider/source HCL.
grep -E '^terraform_version_constraint[[:space:]]*=' "$root/live/root.hcl" > "$fixture/root.hcl"
case "${1:-}" in
  '') ;;
  --without-constraint) : > "$fixture/root.hcl" ;; # RED control, fixture only.
  *) echo 'Usage: test-s3-locking.sh [--without-constraint]' >&2; exit 2 ;;
esac
printf 'include "root" { path = "../root.hcl" }\n' > "$fixture/unit/terragrunt.hcl"
# A local, empty module: no source downloads, dependencies, or providers.
printf '# Offline fixture only\n' > "$fixture/unit/main.tf"
cat > "$fixture/bin/terraform" <<'FAKE'
#!/usr/bin/env bash
set -euo pipefail
printf '%s|%s\n' "$0" "$*" >> "$FAKE_TRACE"
case "$*" in
  '-version') printf 'Terraform v%s\n' "$FAKE_VERSION" ;;
  'validate') echo 'Mock validation only; no Terraform resources accessed' ;;
  *) echo "Forbidden fake Terraform command: $*" >&2; exit 97 ;;
esac
FAKE
chmod +x "$fixture/bin/terraform"
cp "$fixture/bin/terraform" "$fixture/alternate/terraform-custom"

check_version() {
  local version=$1 expected=$2 executable=$3 result=0
  : > "$fixture/trace"
  # Empty environment prevents inherited credentials, endpoint overrides,
  # executable selection, hooks, or auto-init configuration leaking in.
  env -i PATH="$fixture/bin:/usr/bin:/bin" HOME="$fixture/home" \
    FAKE_VERSION="$version" FAKE_TRACE="$fixture/trace" \
    "$terragrunt" --non-interactive --working-dir "$fixture/unit" \
    run --no-auto-init --tf-path "$executable" -- validate \
    > "$fixture/output" 2>&1 || result=$?
  if [[ "$expected" == reject ]]; then
    if [[ $result == 0 ]]; then
      echo "FAIL: Terraform $version was accepted ($executable)" >&2
      exit 1
    fi
    [[ $result == 1 ]] || { echo "FAIL: unexpected rejection exit $result" >&2; exit 1; }
    grep -Eq 'currently installed version .* is not compatible.*>= 1.10.0' "$fixture/output" || {
      cat "$fixture/output" >&2; echo 'FAIL: rejection was not a version constraint' >&2; exit 1;
    }
    # Version discovery is permitted; the requested command must not execute.
    if grep -Fq '|validate' "$fixture/trace"; then
      echo 'FAIL: rejected executable reached requested command' >&2; exit 1
    fi
  else
    if [[ $result != 0 ]]; then cat "$fixture/output" >&2; exit 1; fi
    grep -Fxq "$executable|validate" "$fixture/trace" || {
      echo 'FAIL: selected executable did not run validate' >&2; exit 1;
    }
  fi
  grep -Fxq "$executable|-version" "$fixture/trace" || {
    echo 'FAIL: selected executable was not queried for its version' >&2; exit 1;
  }
  if grep -Fvx -e "$executable|-version" -e "$executable|validate" "$fixture/trace"; then
    echo 'FAIL: unexpected executable or command in trace' >&2; exit 1
  fi
  echo "PASS: $version $expected ($executable)"
}

check_version 1.9.8 reject "$fixture/bin/terraform"
check_version 1.10.0 allow "$fixture/bin/terraform"
check_version 1.11.4 allow "$fixture/bin/terraform"
check_version 1.9.8 reject "$fixture/alternate/terraform-custom"
check_version 1.10.5 allow "$fixture/alternate/terraform-custom"

# Supplement the real boundary with assertions protecting shared backend values.
for contract in \
  'terraform_version_constraint = ">= 1.10.0"' \
  'use_lockfile = true' \
  'key          = "${path_relative_to_include()}/terraform.tfstate"' \
  'state_region = get_env("TG_STATE_REGION", "us-east-2")' \
  'state_bucket = get_env("TG_STATE_BUCKET", "dealengine-demo-tf-eks-state-bucket")' \
  'region       = local.state_region' \
  'bucket = local.state_bucket' \
  'encrypt      = true'; do
  grep -Fq "$contract" "$root/live/root.hcl" || {
    echo "FAIL: missing root contract: $contract" >&2; exit 1;
  }
done
if grep -Eq 'dynamodb_table|TG_LOCK_TABLE' "$root/live/root.hcl"; then
  echo 'FAIL: shared root still selects DynamoDB locking' >&2; exit 1
fi
echo 'PASS: shared root S3 locking contract'
