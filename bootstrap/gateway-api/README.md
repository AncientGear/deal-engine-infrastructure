# Gateway CRD bootstrap

This is the explicit platform bootstrap for Gateway API and AWS Load Balancer Controller (AWS LBC) Gateway CRDs. It deliberately runs outside Terraform state: CRD lifecycle is platform-owned, and Terraform must never create, delete, or invoke it through `local-exec`.

## Quick path

1. Install `bash`, `curl`, `sha256sum`, and a `kubectl` version that supports server-side apply and diff.
2. Inspect the selected cluster explicitly:

   ```bash
   ./gateway-crds.sh diff --context <context-name>
   ```

3. Review the diff. Apply only after that review:

   ```bash
   ./gateway-crds.sh apply --context <context-name>
   ```

The context argument is mandatory. The script never falls back to the current `kubectl` context.

## Pinned inputs and verification

| Bundle | Version | Source | SHA-256 |
| --- | --- | --- | --- |
| Gateway API standard channel | `v1.6.0` | `https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.6.0/standard-install.yaml` | `a557172e8348f758479e9ee4000bbbb4b4aa48302a6b73461823ea5349bad56d` |
| AWS LBC Gateway CRDs | `v3.5.0` | `https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/v3.5.0/config/crd/gateway/gateway-crds.yaml` | `fce68bbfc74b4ed7dbea675f46981cbef1fffc8981cf19c0c1e7a2e9d6464862` |

Each run downloads both bundles into a newly created temporary directory, retries failed downloads at most three times, verifies **both** SHA-256 values, and only then calls `kubectl`. The temporary directory is removed on exit.

`apply` uses server-side apply with the stable field manager `deal-engine-gateway-crd-bootstrap`, then waits up to 120 seconds per expected CRD for `Established`. The expected resources are all CRDs in the Gateway API v1.6.0 standard release directory and the three CRDs in AWS LBC's `config/crd/gateway` release directory:

- Gateway API: `backendtlspolicies`, `gatewayclasses`, `gateways`, `grpcroutes`, `httproutes`, `listenersets`, `referencegrants`, `tcproutes`, `tlsroutes`, and `udproutes` in `gateway.networking.k8s.io`.
- AWS LBC: `listenerruleconfigurations`, `loadbalancerconfigurations`, and `targetgroupconfigurations` in `gateway.k8s.aws`.

## Operational behavior

- **Idempotency:** re-running `apply` reconciles the same pinned manifests through server-side apply. It does not record CRDs in Terraform state.
- **Diff semantics:** `kubectl diff` exits `0` when no differences exist, `1` when differences exist (an expected inspection result), and greater than `1` on an operational failure. The script preserves those semantics: a diff exits `1`; an error is reported and fails.
- **Required access:** the operator's normal `kubectl` configuration must authorize CRD read/diff/apply and wait operations for the supplied context. No credentials, kubeconfig locations, or secrets are embedded in this repository.
- **No destructive path:** this workflow intentionally has no delete or uninstall command. CRD deletion can remove custom resources and must be a separately reviewed platform operation.

## Upgrades

Upgrade only through a reviewed change that updates the version, official URL, SHA-256, and expected CRD list together. Run `diff` against each intended context, review API compatibility and controller support, then run `apply`. Because CRD drift is outside Terraform state, this script is the explicit reconciliation and verification point.
