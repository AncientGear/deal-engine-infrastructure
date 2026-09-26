#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo 'Usage: destroy-env.sh --env dev|staging|prod --confirm destroy-ENV [--profile PROFILE] [--expected-account 12-DIGIT-ID] [--region REGION] [--state-region REGION] [--state-bucket BUCKET] [--lock-table TABLE] [--skip-ecr-purge] [--auto-approve] --delete-namespaces'
}
env_name='' confirm=''
aws_profile="${AWS_PROFILE:-ahau-2026}"
expected_account=989200477899
aws_region="${AWS_REGION:-${AWS_DEFAULT_REGION:-us-east-2}}"
state_region="${TG_STATE_REGION:-us-east-2}"
state_bucket="${TG_STATE_BUCKET:-dealengine-demo-tf-eks-state-bucket}"
lock_table="${TG_LOCK_TABLE:-dealengine-eks-state-locking-table}"
skip_ecr_purge=false auto_approve=false delete_namespaces=false
seen_env=false seen_confirm=false
while [ "$#" -gt 0 ]; do
  case "$1" in
    --env|--confirm|--profile|--expected-account|--region|--state-region|--state-bucket|--lock-table)
      option="$1"
      if [ "$#" -lt 2 ] || [ -z "$2" ] || [[ "$2" == --* ]]; then echo "Missing value for $option" >&2; exit 1; fi
      case "$option" in
        --env) if [ "$seen_env" = true ]; then echo 'Duplicate --env' >&2; exit 1; fi; env_name="$2"; seen_env=true ;;
        --confirm) if [ "$seen_confirm" = true ]; then echo 'Duplicate --confirm' >&2; exit 1; fi; confirm="$2"; seen_confirm=true ;;
        --profile) aws_profile="$2" ;;
        --expected-account) expected_account="$2" ;;
        --region) aws_region="$2" ;;
        --state-region) state_region="$2" ;;
        --state-bucket) state_bucket="$2" ;;
        --lock-table) lock_table="$2" ;;
      esac
      shift 2 ;;
    --skip-ecr-purge) skip_ecr_purge=true; shift ;;
    --auto-approve) auto_approve=true; shift ;;
    --delete-namespaces) delete_namespaces=true; shift ;;
    --help|-h) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage >&2; exit 1 ;;
  esac
done
case "$env_name" in dev|staging|prod) ;; *) echo 'Required --env dev|staging|prod' >&2; exit 1 ;; esac
if [ "$confirm" != "destroy-$env_name" ]; then echo "Refusing to run. Pass --confirm destroy-$env_name" >&2; exit 1; fi
if [ "$delete_namespaces" != true ]; then
  echo 'Refusing full teardown: EKS destroys namespaces and all their contents too. Pass --delete-namespaces explicitly; --auto-approve is not consent.' >&2
  exit 1
fi
if [[ ! "$expected_account" =~ ^[0-9]{12}$ ]]; then echo 'Expected account must be 12 digits' >&2; exit 1; fi
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"
units=(k8s-gateway k8s-namespaces alb-certificate eks-addons lbc-irsa eks rds network-services s3-cloudfront frontend-certificate ecr vpc)
for unit in "${units[@]}"; do
  [ -f "live/$env_name/$unit/terragrunt.hcl" ] || { echo "Required unit config missing: live/$env_name/$unit/terragrunt.hcl" >&2; exit 1; }
done
command -v python3 >/dev/null || { echo 'python3 is required' >&2; exit 1; }
for variable in ${!AWS_ENDPOINT_URL_@}; do unset "$variable"; done
unset AWS_ENDPOINT_URL AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN
export AWS_IGNORE_CONFIGURED_ENDPOINT_URLS=true AWS_PROFILE="$aws_profile" AWS_REGION="$aws_region" AWS_DEFAULT_REGION="$aws_region"
export TG_STATE_REGION="$state_region" TG_STATE_BUCKET="$state_bucket" TG_LOCK_TABLE="$lock_table"
account_id="$(aws sts get-caller-identity --profile "$aws_profile" --query Account --output text)"
if [ "$account_id" != "$expected_account" ]; then echo "Account mismatch: expected $expected_account, got $account_id" >&2; exit 1; fi
caller_arn="$(aws sts get-caller-identity --profile "$aws_profile" --query Arn --output text)"
echo "About to destroy $env_name infrastructure (destructive; data loss possible)"
echo "  account: $account_id; caller: $caller_arn; region: $aws_region"
echo "  state: s3://$state_bucket ($state_region), lock table $lock_table"
if [ "$env_name" = prod ]; then echo 'WARNING: production requires a final RDS snapshot; snapshot or bucket protection may block teardown.' >&2; fi
if [ -t 0 ]; then
  read -r -p "Type destroy-$env_name again to continue: " typed
  if [ "$typed" != "destroy-$env_name" ]; then echo 'Confirmation mismatch. Aborting.' >&2; exit 1; fi
fi
terragrunt_destroy() {
  local unit="$1"
  echo "==> Destroying live/$env_name/$unit"
  (
    cd "live/$env_name/$unit"
    terragrunt init -input=false -no-color
    if [ "$auto_approve" = true ]; then terragrunt destroy -input=false -auto-approve -no-color
    else terragrunt destroy -no-color; fi
  )
}
purge_ecr_repository() {
  local repository="$env_name-dealengine-ecr-repo" error_output image_ids response batch
  if [ "$skip_ecr_purge" = true ]; then echo "Skipping ECR purge for $repository"; return 0; fi
  if ! error_output="$(aws ecr describe-repositories --profile "$aws_profile" --region "$aws_region" --repository-names "$repository" 2>&1)"; then
    if [[ "$error_output" == *RepositoryNotFoundException* ]]; then echo "ECR repository not found: $repository"; return 0; fi
    echo "Cannot inspect ECR repository $repository: $error_output" >&2; return 1
  fi
  image_ids="$(aws ecr list-images --profile "$aws_profile" --region "$aws_region" --repository-name "$repository" --query imageIds --output json)"
  [ "$image_ids" != '[]' ] || return 0
  # Process substitution hides producer errors; build and validate batches first.
  local batches
  batches="$(python3 -c 'import json,sys; ids=json.loads(sys.argv[1]); assert isinstance(ids,list); [print(json.dumps(ids[i:i+100])) for i in range(0,len(ids),100)]' "$image_ids")" || return 1
  while IFS= read -r batch; do
    [ -n "$batch" ] || continue
    response="$(aws ecr batch-delete-image --profile "$aws_profile" --region "$aws_region" --repository-name "$repository" --image-ids "$batch")" || return 1
    python3 -c 'import json,sys; failures=json.load(sys.stdin)["failures"]; print(failures,file=sys.stderr) if failures else None; sys.exit(bool(failures))' <<<"$response" || return 1
  done <<<"$batches"
}
for unit in "${units[@]}"; do
  if [ "$unit" = ecr ]; then purge_ecr_repository; fi
  terragrunt_destroy "$unit"
done
echo 'Destroy sequence completed. Shared platform and Terraform state backend were preserved.'
