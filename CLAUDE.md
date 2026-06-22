# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Architecture

W'xOps Core is the control-plane "brain" of W'xOps, built on **Crossplane v2** combined with **provider-terraform** and **provider-kubernetes** — not on hand-written controllers. A prior `kubebuilder` Go controller was **rejected and removed**. Do not reintroduce a from-scratch Go controller.

### Two composition engines

| Engine | Used by | When to use |
|---|---|---|
| `function-patch-and-transform` | `gitea-*`, `random-password` | Simple single-resource inline HCL `Workspace` |
| `function-kcl` | `platform-database-clusters`, `tenant-database`, `tenant-app` | Multi-resource, conditional branching, list comprehensions |

`tenant-database` additionally uses `function-extra-resources` as a first pipeline step to discover shared clusters via label selector before the KCL step renders resources.

### KCL source management

`kcl/{pkg}/main.k` is the **single source of truth**. It is embedded into `package/{pkg}/composition.yaml` via `make kcl-sync` because `crossplane xpkg build` only packages the Configuration directory. A pre-commit hook (`kcl-drift-check`) enforces sync — always commit both `kcl/{pkg}/main.k` and `package/{pkg}/composition.yaml` together.

```bash
make kcl-sync    # re-embed main.k into composition.yaml (run after editing KCL)
make kcl-check   # fail if composition.yaml has drifted from kcl/{pkg}/main.k
```

### KCL conventions

- Read inputs: `oxr = option("params").oxr`, `params = oxr.spec.parameters`.
- Extra resources (tenant-database): `option("params").extraResources`.
- Use `_get(d, "key", default)` helper instead of `params.get("key", default)` — the latter returns `Undefined` for unset XRD fields in function-kcl.
- KCL has no `if/elif/else` variable assignment — use chained ternary: `x = a if cond1 else b if cond2 else c`.
- KCL `sorted()` does not support `key=` parameter — use `min()` + list filter instead.
- Each composed resource wraps as a `kubernetes.crossplane.io/v1alpha2 Object` with `spec.forProvider.manifest`.
- Use dxr update (emit item with XR's own apiVersion/kind) to write labels and status back to the XR.

### Vault path convention

KCL `remoteKey` values omit the KV mount prefix because the `ClusterSecretStore` is already scoped to it:
- Platform store scoped to `platform/` → code writes `database-clusters/{clusterName}/...` (not `platform/database-clusters/...`)
- Tenant store scoped to `tenants/` → code writes `{owner}/databases/{dbName}/...` (not `tenants/{owner}/...`)

Documentation shows the full logical path (e.g. `tenants/{owner}/databases/{dbName}/connection-creds`).

## Packages

Seven Crossplane Configuration packages plus one utility:

| Package | Kind | Composition |
|---|---|---|
| `gitea-user` | `XGiteaUser` | patch-and-transform + inline HCL |
| `gitea-org` | `XGiteaOrg` | patch-and-transform + inline HCL |
| `gitea-team` | `XGiteaTeam` | patch-and-transform + inline HCL |
| `gitea-repository` | `XGiteaRepository` | patch-and-transform + inline HCL |
| `platform-database-clusters` | `XPlatformDatabaseCluster` | function-kcl |
| `tenant-database` | `XTenantDatabase` | function-extra-resources + function-kcl |
| `tenant-app` | `XTenantApp` | function-kcl |
| `random-password` | `XRandomPassword` | utility, not published as OCI |

Package versions and XRD API versions are tracked in `VERSIONS.yaml`.

## Directory layout

- `package/<name>/` — `xrd.yaml`, `composition.yaml`, `crossplane.yaml`, `kustomization.yaml`, `README.md`
- `package/install/` — production OCI registry-based install (`Configuration` resources, auto-bumped by CI)
- `package/dev/` — development install (applies XRDs + Compositions directly)
- `providers/` — shared provider/function installs and `ProviderConfig` (apply once per cluster)
- `kcl/<name>/` — KCL composition source (`kcl.mod`, `main.k`)
- `examples/<name>/` — minimal XR YAML to exercise each package
- `docs/` — per-XRD `spec.parameters` API reference
- `release-notes/` — hand-written notes for significant releases (CI merges with git-cliff output)

When adding new work, place it in the matching directory. Do not create new top-level folders.

## Commands

```bash
# KCL workflow (run after editing any kcl/{pkg}/main.k)
make kcl-sync                          # embed KCL into composition.yaml
make kcl-check                         # verify sync without modifying

# Build & publish
make build                             # build all OCI packages locally
make push REGISTRY=ghcr.io/wxops VERSION=v0.1.0  # build + push
make validate                          # crossplane xpkg build (no push)

# Lint & render
make lint                              # yamllint + kubeconform
make render                            # offline dry-run of example XRs
pre-commit run --all-files             # all hooks (yaml, kubeconform, xpkg build, kcl drift, versions)

# Cluster install
make providers                         # install providers/functions once per cluster
make install                           # install from OCI registry (production)
make install-dev                       # apply XRDs + Compositions directly (development)

# Release
make release VERSION=vX.Y.Z            # changelog + tag (no push)
make release BUMP=patch                # auto-increment from last tag
make release-notes VERSION=vX.Y.Z      # scaffold release notes from template
make changelog                          # regenerate CHANGELOG.md (requires git-cliff)
```

**Python venv**: activate `~/.python3-venv/bin/activate` before running `git-cliff`, `pre-commit`, or other pip-installed CLIs.

## Pre-commit hooks

Commits are validated by:
1. **Conventional commit** format (commit-msg stage) — types: `feat`, `fix`, `perf`, `refactor`, `docs`, `test`, `chore`, `revert`
2. **YAML lint** + **kubeconform** schema validation
3. **Crossplane xpkg build** for all packages
4. **KCL drift check** — composition.yaml must match kcl/{pkg}/main.k
5. **VERSIONS.yaml bump check** — changed packages must have a version bump

## Working model

When adding new capabilities:

1. Define an `XRD` under `package/<name>/xrd.yaml` — schema-first, keep it minimal.
2. Write a `Composition` under `package/<name>/composition.yaml` — inline HCL for single-resource, KCL function for multi-resource.
3. If using KCL, write `kcl/<name>/main.k` and run `make kcl-sync`.
4. Add `crossplane.yaml` (package metadata) to the same package directory.
5. Add a minimal `examples/<name>/xr.yaml` that exercises the XRD.

Start simple before reaching for advanced patterns.

## CI

`.gitea/workflows/publish-packages.yaml` triggers on `v*` tag push, builds all packages in parallel, pushes versioned + `latest` tags, and auto-commits updated install files back to main.

## Reference stack

| Component | Version |
|---|---|
| Crossplane | v2.3 |
| provider-terraform | v1.1.5 |
| provider-kubernetes | v1.2.1 |
| provider-sql | v0.15.0 |
| function-kcl | v0.12.1 |
| function-extra-resources | v0.3.0 |
| function-patch-and-transform | v0.10.7 |
| function-go-templating | v0.12.2 |
| Gitea Terraform provider | ~> 0.7.0 |
