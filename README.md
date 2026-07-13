# W'xOps Core

Control-plane "brain" of W'xOps. Exposes Gitea management, PostgreSQL database provisioning, and tenant application scaffolding (with Darlane in-cluster developer workspaces) as Kubernetes-native platform APIs via [Crossplane v2](https://docs.crossplane.io/v2.3/) Configuration packages backed by `provider-terraform`, `provider-kubernetes`, and `function-kcl`.

## Packages

<!-- packages-table-start -->
| Package | Kind | Group | API Versions | Package Version |
|---|---|---|---|---|
| [`gitea-user`](package/gitea-user/) | `XGiteaUser` | `platform.wxops.cloud` | `v1alpha1` | `v0.1.1` |
| [`gitea-org`](package/gitea-org/) | `XGiteaOrg` | `platform.wxops.cloud` | `v1alpha1` | `v0.1.1` |
| [`gitea-team`](package/gitea-team/) | `XGiteaTeam` | `platform.wxops.cloud` | `v1alpha1` | `v0.1.1` |
| [`gitea-repository`](package/gitea-repository/) | `XGiteaRepository` | `platform.wxops.cloud` | `v1alpha1` | `v0.1.0` |
| [`platform-database-clusters`](package/platform-database-clusters/) | `XPlatformDatabaseCluster` | `platform.wxops.cloud` | `v1alpha1` | `v0.1.4` |
| [`tenant-database`](package/tenant-database/) | `XTenantDatabase` | `platform.wxops.cloud` | `v1alpha1` | `v0.1.4` |
| [`tenant-app`](package/tenant-app/) | `XTenantApp` | `platform.wxops.cloud` | `v1alpha1` | `v0.2.2` |
<!-- packages-table-end -->

> `random-password` lives in `package/random-password/` as a utility composition but is not yet published as a standalone OCI package.

Current package versions and XRD API version history are tracked in [`VERSIONS.yaml`](VERSIONS.yaml). Full `spec.parameters` reference for every XRD lives in [`docs/`](docs/).

---

## Why Crossplane + Terraform

The previous direction used `kubebuilder` to build a controller from scratch. That was **rejected** — too much complexity for the problem.

The current approach combines two tools with clear roles:

- **Crossplane** owns the platform API layer: `XRD`s define the schema, `Composition`s wire them to infrastructure, and the control loop reconciles desired state.
- **Terraform** (via `provider-terraform`) owns the infrastructure execution: each `Workspace` resource runs a plan/apply cycle in-cluster against a Gitea Terraform provider.

Composition functions may be written in Python, Go, CEL, KCL, or Go templating. The `kcl/` directory holds KCL-based composition logic for `platform-database-clusters`, `tenant-database`, and `tenant-app` — see [KCL composition functions](#kcl-composition-functions) below.

---

## Repository layout

```
package/                      ← Crossplane Configuration packages
  gitea-user/
    xrd.yaml                  ← XCompositeResourceDefinition (schema)
    composition.yaml          ← Composition (inline HCL Workspace)
    crossplane.yaml           ← Package descriptor for xpkg build (meta.pkg.crossplane.io/v1)
    kustomization.yaml        ← dev kustomize root (xrd + composition only)
    README.md
  gitea-org/
  gitea-team/
  gitea-repository/
  random-password/            ← utility composition, no package metadata yet
  install/                    ← Production install: OCI registry-based (pkg.crossplane.io/v1)
    gitea-user.yaml           ← Configuration resource; spec.package auto-bumped by CI
    gitea-org.yaml
    gitea-team.yaml
    gitea-repository.yaml
    kustomization.yaml        ← kubectl apply -k package/install/
  dev/
    kustomization.yaml        ← Development install: applies XRDs+Compositions directly
                              ← kubectl apply -k package/dev/
  kustomization.yaml          ← delegates to install/ (kubectl apply -k package/)
providers/                    ← shared Provider + Function installs + ProviderConfig
docs/                         ← API reference (spec.parameters) per XRD
examples/                     ← minimal XR YAML to exercise each package
  gitea-user/
    credentials-secret.yaml
    xr.yaml
  gitea-org/xr.yaml
  gitea-team/xr.yaml
  gitea-repository/xr.yaml
  random-password/xr.yaml
  platform-database-clusters/xr.yaml
  tenant-database/xr.yaml
  tenant-database/xr-dedicated.yaml
  tenant-app/xr.yaml
kcl/                          ← KCL composition functions (source of truth, embedded via kcl-sync)
  platform-database-clusters/
    kcl.mod
    main.k
  tenant-database/
    kcl.mod
    main.k
  tenant-app/
    kcl.mod
    main.k
.gitea/workflows/
  publish-packages.yaml       ← CI: build + push on v* tag, auto-bump package/install/
```

---

## Getting started

### Prerequisites

- [`crossplane` CLI](https://docs.crossplane.io/latest/cli/) ≥ v2.3
- `kubectl` pointed at a cluster with Crossplane v2.3+ installed
- `pre-commit` (optional, for local development)

### 1 — Install providers once per cluster

```bash
make providers
```

This applies everything in `providers/`: `provider-terraform`, `provider-kubernetes` (+ RBAC and `ProviderConfig`), `provider-sql`, `function-patch-and-transform`, `function-go-templating`, `function-kcl`, `function-extra-resources`, and the Terraform `ProviderConfig`.

>[!NOTE]
> `make providers` is required before `make install`.** Crossplane's
> `dependsOn` in `crossplane.yaml` can auto-install missing dependencies, but
> auto-installed resources get long names derived from the OCI path (e.g.
> `crossplane-contrib-function-kcl` instead of `function-kcl`). Compositions
> reference the short names set by `providers/*.yaml`, so auto-installed
> dependencies will not be found. Additionally, providers like
> `provider-kubernetes` need a `RuntimeConfig`, RBAC `ClusterRoleBinding`, and
> `ProviderConfig` — none of which `dependsOn` can provide. The `dependsOn`
> section serves as a **version constraint safety net**, not an installer.

### 2 — Create a credentials secret

All packages use the same secret format:

```bash
kubectl create secret generic gitea-credentials \
  --from-literal=credentials='gitea_token = "your-admin-token"' \
  -n crossplane-system
```

For `gitea-user`, append a `password` field:

```bash
kubectl create secret generic gitea-credentials \
  --from-literal=credentials=$'gitea_token = "your-admin-token"\npassword = "initial-password"' \
  -n crossplane-system
```

### 3 — Install packages

**Production** (pulls from OCI registry):

```bash
make install
```

**Development** (applies XRDs + Compositions directly, no registry):

```bash
make install-dev
```

### 4 — Apply an example claim

```bash
kubectl apply -f examples/gitea-user/xr.yaml
kubectl get xgiteausers
kubectl describe xgiteauser <name>
```

---

## Development

### Pre-commit hooks

Install once:

```bash
pip install pre-commit
pre-commit install
```

On every `git commit`, hooks run:

| Hook | Tool | What it checks |
|---|---|---|
| YAML syntax | `check-yaml` | All `.yaml`/`.yml` files parse cleanly |
| YAML style | `yamllint` | Line length, indentation, key ordering |
| Kubernetes schema | `kubeconform` | XRDs, Compositions, providers match API schemas |
| Package render | `crossplane xpkg build` | All four packages build without errors |

Run all hooks manually without committing:

```bash
pre-commit run --all-files
```

Run only the Crossplane build validation:

```bash
pre-commit run crossplane-validate --all-files
```

### Make targets

```
make build         Build all OCI packages locally (.xpkg artifacts)
make push          Build + push to registry  (set REGISTRY= and VERSION=)
make validate      Validate package structure (crossplane xpkg build, no push)
make lint          YAML lint + kubeconform
make render        Render example XRs against compositions (offline dry-run)
make providers     Install shared providers/functions on cluster
make install       Install packages from OCI registry
make install-dev   Apply XRDs + Compositions directly (no registry)
make uninstall     Remove registry-installed packages
make uninstall-dev Remove dev-applied XRDs + Compositions
make changelog     Generate CHANGELOG.md from git log (requires git-cliff)
make clean         Remove .xpkg build artifacts
make help          Show all targets
```

---

## KCL composition functions

`platform-database-clusters`, `tenant-database`, and `tenant-app` use [`function-kcl`](https://github.com/crossplane-contrib/function-kcl) instead of `function-go-templating`, since their Compositions need real branching/looping across multiple optional resources (conditional resource sets, dict merges, list comprehensions over arrays like `managedRoles[]`, and — for `tenant-app` — composing a nested `XTenantDatabase` XR). The other packages (`gitea-*`, `random-password`) are simple enough that inline HCL / Go templating is sufficient.

`kcl/{pkg}/main.k` is the source of truth and is embedded into `package/{pkg}/composition.yaml` via `make kcl-sync` / `make kcl-check`.

See [`kcl/README.md`](kcl/README.md) for why KCL vs Go templating, the sync workflow, how to wire a new KCL module into an XRD, and the deferred OCI-modules migration plan.

---

## Versioning

Two independent versioning axes exist in this project:

| Axis | Example | Tracked in | When it changes |
|---|---|---|---|
| **Package version** | `v0.2.0` | `configuration.yaml` → `spec.package` | On every git tag push; CI auto-bumps |
| **XRD API version** | `v1alpha1` | `xrd.yaml` → `spec.versions[].name` | When a schema version is added or deprecated |

Both axes are summarised in [`VERSIONS.yaml`](VERSIONS.yaml).

### XRD versioning rules

- **Never remove** a `served: true` version — that is a breaking change for cluster consumers.
- **Adding** a new version (e.g. `v1alpha1` → `v1beta1`) requires a `conversion` strategy in the XRD and should bump the package **minor** version.
- **Schema changes within a version** that are backward-compatible (adding optional fields) can ship as a **patch** release.
- **Removing required fields or changing field types** is a breaking change — add a new API version instead.

### Releasing a new package version

```bash
git tag v0.2.0
git push origin v0.2.0
```

CI (`.gitea/workflows/publish-packages.yaml`) will:
1. Build all four packages in parallel.
2. Push `<image>:v0.2.0` and `<image>:latest` to the registry.
3. Auto-commit updated `configuration.yaml` files with the new `spec.package` image back to `main`.

### Changelog

Generated from [Conventional Commits](https://www.conventionalcommits.org/) via [`git-cliff`](https://git-cliff.org/):

```bash
make changelog        # regenerate CHANGELOG.md
make changelog-preview  # print to stdout, don't write file
```

Use package names as scopes to keep per-package history readable:

```
feat(gitea-team): add includeAllRepositories field to XRD v1alpha1
fix(gitea-user): correct must_change_password terraform variable default
feat(gitea-repository)!: promote schema to v1beta1 — breaking field rename
chore(ci): pin crossplane CLI to v2.3.1 in publish workflow
```

---

## Reference stack

| Component | Version | Reference |
|---|---|---|
| Crossplane | v2.3 | https://docs.crossplane.io/v2.3/ |
| provider-terraform | v1.1.5 | https://marketplace.upbound.io/providers/upbound/provider-terraform/v1.1.5 |
| function-patch-and-transform | v0.10.7 | https://marketplace.upbound.io/functions/crossplane-contrib/function-patch-and-transform/v0.10.7 |
| function-go-templating | v0.12.2 | https://marketplace.upbound.io/functions/crossplane-contrib/function-go-templating/v0.12.2 |
| function-kcl | v0.12.1 | https://marketplace.upbound.io/functions/crossplane-contrib/function-kcl/v0.12.1 |
| function-extra-resources | v0.3.0 | https://marketplace.upbound.io/functions/crossplane-contrib/function-extra-resources/v0.3.0 |
| Gitea Terraform provider | ~> 0.7.0 | https://registry.terraform.io/providers/go-gitea/gitea/latest/docs |
