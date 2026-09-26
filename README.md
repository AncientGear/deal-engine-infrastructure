# Deal Engine Infrastructure

This repository owns the live Terraform/Terragrunt configuration for the Deal Engine platform environments.

Each environment under `live/` is modeled as a separate EKS-based stack:

- `live/dev`
- `live/staging`
- `live/prod`

The reusable modules are versioned from `git@github.com:AncientGear/infrastructure-modules.git`.

## Environment model

The current live model uses one EKS cluster per environment.

Node scheduling metadata still follows the workload isolation intent from the architecture proposal:

- `dev` and `staging` node groups use `workload=shared` labels and taints.
- `prod` node groups use `workload=prod` labels and taints.

Application Helm charts must set matching `nodeSelector` and `tolerations`; otherwise Kubernetes will not schedule workloads onto these tainted node groups.

## Local AWS simulation with Floci

Use Floci before touching a real AWS account when you want fast syntax, dependency, and state-backend validation.

Start the emulator from this repository:

```bash
docker compose up -d
```

If your Docker CLI is accidentally pointing at an unavailable Docker Desktop context, run the same command with the local engine context:

```bash
DOCKER_CONTEXT=default docker compose up -d
```

Export the local AWS-compatible endpoint and dummy credentials:

```bash
export AWS_ENDPOINT_URL=http://localhost:4566
export AWS_DEFAULT_REGION=us-east-2
export AWS_ACCESS_KEY_ID=test
export AWS_SECRET_ACCESS_KEY=test
export TG_STATE_REGION=us-east-2
export TG_STATE_BUCKET=dealengine-demo-tf-eks-state-bucket
export TG_LOCK_TABLE=dealengine-eks-state-locking-table
```

Bootstrap the Terraform remote-state bucket and lock table inside Floci:

```bash
./scripts/floci-bootstrap-state.sh
```

Floci is for pre-AWS validation only. Treat successful Floci plans as evidence that the Terraform/Terragrunt wiring is coherent, not as proof that AWS-managed services such as EKS, ACM, RDS, or AWS Load Balancer Controller will behave identically in AWS.

Known limitation: Floci can mock the EKS control-plane AWS API well enough for Terraform plans, but it does not provide a real Kubernetes API server. Kubernetes/Helm units such as `eks-addons` and `k8s-gateway` can plan against simulated EKS metadata, but their applies require a reachable Kubernetes cluster with valid credentials.

## Dev apply order

Start with `dev`. Do not apply every unit at once until the dependency chain has been proven.

Recommended order:

1. `live/dev/vpc`
2. `live/dev/ecr`
3. `live/platform/platform-images/aws-load-balancer-controller`
4. Mirror the AWS Load Balancer Controller image with `scripts/mirror-platform-image.sh`
5. `live/dev/network-services`
6. `live/dev/rds`
7. `live/dev/eks`
8. `live/dev/lbc-irsa`
9. Gateway API CRD bootstrap
10. `live/dev/eks-addons`
11. `live/dev/alb-certificate`
12. `live/dev/k8s-namespaces`
13. `live/dev/k8s-gateway`
14. `live/dev/s3-cloudfront`

### Why this order

- `vpc` creates the networking base consumed by most other units.
- `ecr` is independent and can be created early.
- `platform-images` creates private ECR repositories for platform addon image mirrors.
- The mirror script copies required public addon images into private ECR before nodes need to pull them.
- `network-services` creates private AWS service endpoints required by nodes running in private subnets without NAT.
- `rds` depends on VPC subnets and security boundaries.
- `eks` depends on VPC private app subnets and uses a private API endpoint so managed nodes can join without outbound internet access.
- `lbc-irsa` depends on EKS OIDC outputs and VPC identity.
- Gateway API CRDs must exist before Terraform can manage Gateway API resources through the Kubernetes provider.
- `eks-addons` installs AWS Load Balancer Controller and depends on the IRSA role.
- `alb-certificate` provides the regional ACM certificate used by the Gateway listener.
- `k8s-namespaces` depends on EKS and owns `gateway-system` and `backend-dev`.
- `k8s-gateway` depends on the namespace unit (and therefore EKS), AWS Load Balancer Controller, VPC private subnets, and the ALB certificate.
- `s3-cloudfront` can be validated after the platform ingress path is clearer.

## Environment teardown

**MIGRATION REQUIRED BEFORE APPLY OR DESTROY on existing clusters.** Published modules are wired at `live/{dev,staging,prod}/k8s-namespaces` (`k8s-namespaces-v0.1.0`) and `k8s-gateway-v0.2.0`. On an existing cluster, migrate namespace ownership before applying either unit or destroying the environment. Do not treat a new empty namespace state as a backup or let both units own the same namespace.

### Manual namespace state migration (dev; do not execute automatically)

This is a gated operator procedure, **not** one copy-paste script. Freeze normal applies and destroys for both units throughout dual ownership; only the reviewed namespace **refresh-only** plan below may be applied during that interval. Confirm the intended AWS account, cluster, backend, environment, and Kubernetes context at every gate. Store state backups as sensitive files **outside this repository** with restricted permissions; never commit them. Stop on any error or unexpected address.

1. **Back up the old Gateway state before changing live Gateway HCL.** If live Gateway HCL has already been updated to depend on namespace outputs, do **not** run Gateway `state list`, `state pull`, or `state rm` through that configuration: dependency output mocks cover plan/validate only. Instead, use a separately checked-out, known old infrastructure revision `7690e9f` with the *same* backend, environment, credentials/account, and cluster, exclusively for Gateway state backup/read and, at gate 4, removal. Do not apply or destroy from that checkout. If its identity or backend cannot be confirmed, stop rather than trying an automatic fallback. From the old configuration's `live/dev/k8s-gateway`, run each command separately:

   ```bash
   umask 077
   terragrunt state list
   terragrunt state pull > "$HOME/deal-engine-state-backups/dev-k8s-gateway-before-namespace-migration.tfstate"
   ```

   Create the external backup directory securely beforehand. Confirm both exact root addresses `kubernetes_namespace_v1.platform` and `kubernetes_namespace_v1.authorized_application["backend-dev"]` in the list, and verify the backup is complete and protected before proceeding. Never overwrite a prior backup.

2. **Initialize and import into the new namespace unit.** In the current infrastructure checkout's `live/dev/k8s-namespaces`, initialize its backend (`terragrunt init`), then inspect `terragrunt state list`. If state listing fails, stop; if it contains resources, back up that existing state with `terragrunt state pull` to a separate protected external file before importing. Verify the existing cluster objects `gateway-system` and `backend-dev` and the target account/context. Import only addresses not already owned by this namespace state, one at a time:

   ```bash
   terragrunt import kubernetes_namespace_v1.platform gateway-system
   terragrunt import 'kubernetes_namespace_v1.authorized_application["backend-dev"]' backend-dev
   ```

   Re-list namespace state and verify **both** exact imported bindings and their remote object identities. Do not manufacture an empty-state backup or re-import an owned address.

3. **Populate the namespace outputs without a normal infrastructure apply.** From the current `live/dev/k8s-namespaces`, save a refresh-only plan, inspect it for unexpected changes and correct namespace identities, then apply **that exact saved plan** only after review:

   ```bash
   terragrunt plan -refresh-only -out="$HOME/deal-engine-state-backups/dev-namespace-refresh.tfplan"
   terragrunt show "$HOME/deal-engine-state-backups/dev-namespace-refresh.tfplan"
   terragrunt apply "$HOME/deal-engine-state-backups/dev-namespace-refresh.tfplan"
   terragrunt output
   ```

   A refresh-only apply updates state/outputs, not managed infrastructure; it is the sole allowed apply while both states own the namespaces. Treat the saved plan as sensitive; use a protected external path and never overwrite an existing plan. Confirm the namespace outputs required by Gateway are present and correct before any Gateway state command. If output checks fail, stop with normal applies/destroys frozen.

4. **Remove only old Gateway bindings.** Use the verified old-configuration checkout from gate 1, with the same backend/environment/account. Run `terragrunt state list` again from its `live/dev/k8s-gateway`; confirm the two exact root addresses and the protected Gateway backup. Only then run:

   ```bash
   terragrunt state rm kubernetes_namespace_v1.platform 'kubernetes_namespace_v1.authorized_application["backend-dev"]'
   ```

   Verify both addresses are absent from Gateway state and still present in namespace state. If addresses differ or any step partially fails, stop, keep normal applies/destroys frozen, inspect both states and backups, and resolve ownership manually. Then inspect ordinary plans for both units from the **current** checkout; neither may show unexpected recreation, deletion, or change before resuming normal applies. For staging and prod, repeat these gates only where those clusters and Gateway namespace state actually exist, with environment-specific backends, objects, outputs, and unique backup/plan paths. For fresh environments apply `k8s-namespaces` before `k8s-gateway` instead.

**Only after required state migration:** select exactly one environment and supply both its matching confirmation and explicit namespace-deletion consent; there is no default or all-environments mode:

```bash
bash scripts/destroy-env.sh --env dev --confirm destroy-dev --delete-namespaces
bash scripts/destroy-env.sh --env staging --confirm destroy-staging --delete-namespaces
bash scripts/destroy-env.sh --env prod --confirm destroy-prod --delete-namespaces
```

`scripts/destroy-dev.sh --confirm destroy-dev --delete-namespaces` remains a dev-only compatibility entry point and rejects `--env` overrides. The scripts validate all 12 selected unit configuration files before contacting AWS, check account `989200477899` by default, and clear inherited AWS endpoint overrides and static credentials. Use `--expected-account` only with a verified 12-digit alternate account. Optional `--profile`, `--region`, `--state-region`, `--state-bucket`, and `--lock-table` select credentials and state. Without `--auto-approve`, Terragrunt prompts for each destroy; `--skip-ecr-purge` leaves images intact and may block ECR destruction. Run `bash scripts/tests/test-destroy-env.sh` for offline mock-only checks; Python 3 is required for bounded ECR image deletion.

**Destructive:** EKS destruction deletes Kubernetes namespaces and **all namespace contents**, even when the namespace unit is managed separately. `--auto-approve` does not replace `--delete-namespaces`. Teardown can permanently remove cluster workloads, databases, networking, and environment-scoped images. Review backups and plans before proceeding. Production requires an RDS final snapshot; snapshot constraints, deletion protection, or nonempty S3 buckets can block teardown. The script does not bypass protection or automatically empty S3 buckets. Shared platform repositories, backend state bucket/lock table, and backend services are excluded. Residual snapshots, EBS volumes, shared infrastructure, and backend storage/locks may continue to incur costs. CoreDNS addon preservation does **not** protect it when the EKS cluster is destroyed.

## Per-unit workflow

For each unit, use this sequence:

1. Review the unit inputs.
2. Format HCL from `live/` after edits.
3. Validate HCL.
4. Run a plan for the single unit.
5. Read the plan before apply.
6. Apply only when the plan matches intent.

Example command shape from a unit directory:

```bash
terragrunt init
terragrunt plan
terragrunt apply
```

Prefer running commands from the target unit directory so dependency and generated-provider behavior is obvious.

## Gateway API CRD bootstrap

Before applying `live/<env>/k8s-gateway`, bootstrap CRDs against the explicit Kubernetes context for that environment.

From `bootstrap/gateway-api`:

```bash
./gateway-crds.sh diff --context <context-name>
./gateway-crds.sh apply --context <context-name>
```

The context is mandatory. The script intentionally does not fall back to the current `kubectl` context.

## Private addon images

The EKS nodes run in private subnets without NAT. Addon images must be available from private regional ECR so they can be pulled through the VPC endpoints.

Create the private mirror repository with Terraform before applying `live/dev/eks-addons`:

```bash
cd live/platform/platform-images/aws-load-balancer-controller
terragrunt init
terragrunt apply
```

Then mirror the controller image into that repository:

```bash
./scripts/mirror-platform-image.sh aws-load-balancer-controller v3.5.0
```

The script is intentionally generic: add a new image-key mapping when another platform addon needs a private mirror.

## Current module tags

The live stack currently consumes these important platform tags:

- `eks-v0.1.3`
- `eks-irsa-aws-load-balancer-controller-v0.1.1`
- `k8s-addons-v0.1.2`
- `k8s-namespaces-v0.1.0` (`live/{dev,staging,prod}/k8s-namespaces`)
- `k8s-gateway-v0.2.0` (`live/{dev,staging,prod}/k8s-gateway`)

CoreDNS adoption requires inspecting existing addon conflicts before applying: the `NONE` conflict strategy does not overwrite them automatically. `preserve = true` leaves workloads in place when addon management is removed; it does not protect workloads from cluster destruction. Review the plan and apply the change yourself.

## Known follow-ups

- Add the backend Helm chart with matching `nodeSelector` and `tolerations` per environment.
- Add Argo CD Applications after the chart exists.
- Decide how CloudFront will discover or receive the ALB target created asynchronously by AWS Load Balancer Controller.
- Consider whether `dev` and `staging` should remain separate clusters or eventually converge toward the original shared-cluster architecture proposal.
