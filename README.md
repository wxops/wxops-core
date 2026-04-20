# wxops-core — The "Brain"

> [!NOTE]
> Kubernetes controllers and CRDs that power the W'xOps Internal Developer Platform.

## Overview

`wxops-core` is the central control plane of the **W'xOps** ecosystem. Built with [kubebuilder](https://book.kubebuilder.io/), it defines Custom Resources under the **`wxops.cloud`** API group and runs controllers that reconcile platform state — turning developer intent into running infrastructure.

It is the "glue" between the portal ([wxops-portal](../wxops-portal)), the GitOps layer ([wxops-gitops-infrastructure](../wxops-gitops-infrastructure)), and the underlying Kubernetes primitives (Crossplane, Dex, Vault, Kyverno).

### Where it fits

```text
┌─────────────┐     ┌──────────────┐     ┌───────────────────────────┐
│ wxops-portal│────►│  wxops-core  │────►│ wxops-gitops-infrastructure│
│  (The Glass)│     │  (The Brain) │     │       (The Skeleton)       │
└─────────────┘     └──────┬───────┘     └───────────────────────────┘
                           │
              ┌────────────┼────────────┐
              ▼            ▼            ▼
          Crossplane    Dex/OIDC     Vault
          (Infra)     (Identity)   (Secrets)
```

## Project Structure

```text
wxops-core/
├── cmd/
│   └── main.go                    # Controller manager entry point
├── api/                           # CRD type definitions (created via kubebuilder)
│   └── <version>/
│       └── *_types.go             # +kubebuilder markers → generates CRDs
├── internal/
│   └── controller/                # Reconciliation logic per resource
├── config/
│   ├── default/                   # Kustomize: aggregates all config layers
│   ├── manager/                   # Controller manager Deployment
│   ├── rbac/                      # Generated RBAC (ClusterRole, ServiceAccount)
│   ├── prometheus/                # ServiceMonitor for metrics scraping
│   └── network-policy/            # NetworkPolicy for controller traffic
├── test/
│   ├── e2e/                       # End-to-end tests (Kind cluster)
│   └── utils/                     # Test helpers
├── hack/
│   └── boilerplate.go.txt         # License header for generated files
├── Dockerfile                     # Multi-stage build → distroless
├── Makefile                       # Build, test, deploy commands
└── PROJECT                        # Kubebuilder metadata (domain: wxops.cloud)
```

## Prerequisites

- Go **1.25+**
- Docker (or Podman)
- kubectl configured against a cluster
- [Kind](https://kind.sigs.k8s.io/) (for e2e tests)

## Quick Start

```bash
# Generate CRDs and RBAC manifests
make manifests

# Generate DeepCopy implementations
make generate

# Run the controller locally (outside cluster)
make run

# Run unit tests
make test

# Run e2e tests (creates a Kind cluster automatically)
make test-e2e
```

## Build & Deploy

```bash
# Build the manager binary
make build

# Build the container image
make docker-build IMG=<registry>/wxops-core:<tag>

# Push the container image
make docker-push IMG=<registry>/wxops-core:<tag>

# Install CRDs into the cluster
make install

# Deploy the controller to the cluster
make deploy IMG=<registry>/wxops-core:<tag>

# Remove the controller from the cluster
make undeploy
```

## Adding a New API Resource

```bash
# Example: create a DevSpace resource under wxops.cloud/v1alpha1
kubebuilder create api --group wxops --version v1alpha1 --kind DevSpace

# Example: create a webhook for validation
kubebuilder create webhook --group wxops --version v1alpha1 --kind DevSpace \
  --defaulting --programmatic-validation
```

After scaffolding, edit `api/<version>/*_types.go` to define your spec/status fields, then run `make manifests generate`.

## Planned CRDs

| Kind | API Group | Purpose |
|------|-----------|---------|
| `DevSpace` | `wxops.cloud` | Developer workspace provisioning (namespace, quotas, network policies) |
| `ServiceScaffold` | `wxops.cloud` | Trigger scaffolding from wxops-templates into Gitea |
| `DatabaseClaim` | `wxops.cloud` | Request managed database via Crossplane compositions |
| `ObservabilityStack` | `wxops.cloud` | Configure per-tenant LGTM stack (Loki, Grafana, Tempo, Mimir) |

## Linting

```bash
make lint          # Run golangci-lint
make lint-fix      # Auto-fix lint issues
```

## License

Copyright 2026. Licensed under the Apache License, Version 2.0.