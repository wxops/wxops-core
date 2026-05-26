# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository status

The Gitea management layer is fully scaffolded with four independent Crossplane Configuration packages:

- `packages/gitea-user/` — `XGiteaUser` XRD + Composition
- `packages/gitea-org/` — `XGiteaOrg` XRD + Composition
- `packages/gitea-team/` — `XGiteaTeam` XRD + Composition (includes team membership)
- `packages/gitea-repository/` — `XGiteaRepository` XRD + Composition

Each package uses inline HCL in the Composition (via `source: Inline`) — no external Terraform module is needed for these single-resource patterns.

A prior implementation built a Kubernetes controller with `kubebuilder` in Go. That direction was **rejected** and the Go code was removed (see `git log`). Do not reintroduce a from-scratch Go controller.

A bulk Terraform module for multi-org bootstrapping (`gitea-org`) was developed and moved to a separate repository. It is not part of this repo.

## Architectural direction

W'xOps Core is the control-plane "brain" of W'xOps. It is built on **Crossplane v2** combined with **provider-terraform**, not on hand-written controllers.

- **Crossplane** exposes infrastructure as a reusable platform API through `XRD`s, `Composition`s, and `Function`s.
- **Compositions** use `source: Inline` for simple single-resource cases (all four current packages). For complex multi-resource logic, reach for a real Terraform module or a KCL/Go-templating function.
- **provider-terraform** (`upbound/provider-terraform`) bridges Crossplane and Terraform — each `Workspace` resource runs a plan/apply cycle in-cluster.

Composition functions may be written in: Python, Go, CEL, KCL, Go templating. The `kcl/` directory is reserved for KCL-based functions.

## Directory intent

- `packages/<name>/` — Crossplane Configuration package: `xrd.yaml`, `composition.yaml`, `crossplane.yaml`, `configuration.yaml`, `README.md`.
- `providers/` — shared Crossplane provider/function installs and `ProviderConfig`. Apply once per cluster before any packages.
- `kcl/` — KCL sources for composition functions (reserved, not yet populated).
- `examples/<name>/` — minimal XR/claim YAML that exercises the corresponding `packages/<name>/` XRD. One `xr.yaml` per concept; shared credentials example in `examples/gitea-user/credentials-secret.yaml`.

When adding new work, place it in the matching directory. Do not create new top-level folders.

## Reference stack

- Crossplane v2.3 — https://docs.crossplane.io/v2.3/
- Gitea Terraform provider (`go-gitea/gitea` ~> 0.7.0) — https://registry.terraform.io/providers/go-gitea/gitea/latest/docs
- Crossplane Terraform provider (`upbound/provider-terraform` v1.1.4)
- Function Patch and Transform (`crossplane-contrib/function-patch-and-transform` v0.10.6)
- Function Go Templating (`crossplane-contrib/function-go-templating` v0.12.1)

## Working model

Follow this flow when adding new capabilities:

1. Define an `XRD` under `packages/<name>/xrd.yaml` — schema-first, keep it minimal.
2. Write a `Composition` under `packages/<name>/composition.yaml` — inline HCL for single-resource, separate module or KCL function for multi-resource.
3. Add `crossplane.yaml` (package metadata) and `configuration.yaml` (GitOps install resource) to the same package directory.
4. Add a minimal `examples/<name>/xr.yaml` that exercises the XRD end-to-end.

Start simple before reaching for advanced patterns.

## Commands

```bash
# Build all OCI packages locally
make build

# Build and push to registry (set REGISTRY and VERSION as needed)
make push REGISTRY=ghcr.io/wxops VERSION=v0.1.0

# Install providers + functions once per cluster
make providers

# Install packages from registry (production)
make install

# Apply XRDs + Compositions directly — no registry needed (development)
make install-dev

# Remove installs
make uninstall
make uninstall-dev
```

CI: `.gitea/workflows/publish-packages.yaml` triggers on `v*` tag push, builds all four packages in parallel, pushes versioned + `latest` tags, and auto-commits updated `configuration.yaml` files back to main.

Credentials secret format (all packages share the same pattern):

```bash
kubectl create secret generic gitea-credentials \
  --from-literal=credentials='gitea_token = "your-admin-token"' \
  -n crossplane-system
```
