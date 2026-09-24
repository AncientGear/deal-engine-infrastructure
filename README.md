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
3. `live/dev/network-services`
4. `live/dev/rds`
5. `live/dev/eks`
6. `live/dev/lbc-irsa`
7. Gateway API CRD bootstrap
8. `live/dev/eks-addons`
9. `live/dev/alb-certificate`
10. `live/dev/k8s-gateway`
11. `live/dev/s3-cloudfront`

### Why this order

- `vpc` creates the networking base consumed by most other units.
- `ecr` is independent and can be created early.
- `network-services` creates private AWS service endpoints required by nodes running in private subnets without NAT.
- `rds` depends on VPC subnets and security boundaries.
- `eks` depends on VPC private app subnets and uses a private API endpoint so managed nodes can join without outbound internet access.
- `lbc-irsa` depends on EKS OIDC outputs and VPC identity.
- Gateway API CRDs must exist before Terraform can manage Gateway API resources through the Kubernetes provider.
- `eks-addons` installs AWS Load Balancer Controller and depends on the IRSA role.
- `alb-certificate` provides the regional ACM certificate used by the Gateway listener.
- `k8s-gateway` depends on EKS, AWS Load Balancer Controller, VPC private subnets, and the ALB certificate.
- `s3-cloudfront` can be validated after the platform ingress path is clearer.

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

Mirror the AWS Load Balancer Controller image before applying `live/dev/eks-addons`:

```bash
aws ecr get-login-password --profile ahau-2026 --region us-east-2 \
  | docker login --username AWS --password-stdin 989200477899.dkr.ecr.us-east-2.amazonaws.com

aws ecr create-repository \
  --profile ahau-2026 \
  --region us-east-2 \
  --repository-name platform/aws-load-balancer-controller

docker pull public.ecr.aws/eks/aws-load-balancer-controller:v3.5.0

docker tag \
  public.ecr.aws/eks/aws-load-balancer-controller:v3.5.0 \
  989200477899.dkr.ecr.us-east-2.amazonaws.com/platform/aws-load-balancer-controller:v3.5.0

docker push \
  989200477899.dkr.ecr.us-east-2.amazonaws.com/platform/aws-load-balancer-controller:v3.5.0
```

If the repository already exists, the `create-repository` command can be skipped.

## Current module tags

The live stack currently consumes these important platform tags:

- `eks-v0.1.2`
- `eks-irsa-aws-load-balancer-controller-v0.1.1`
- `k8s-addons-v0.1.2`
- `k8s-gateway-v0.1.0`

## Known follow-ups

- Add the backend Helm chart with matching `nodeSelector` and `tolerations` per environment.
- Add Argo CD Applications after the chart exists.
- Decide how CloudFront will discover or receive the ALB target created asynchronously by AWS Load Balancer Controller.
- Consider whether `dev` and `staging` should remain separate clusters or eventually converge toward the original shared-cluster architecture proposal.
