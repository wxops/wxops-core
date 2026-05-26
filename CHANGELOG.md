# Changelog

All notable changes to W'xOps Core packages are documented here.

Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
Versioning follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html).
Commit messages follow [Conventional Commits](https://www.conventionalcommits.org/en/v1.0.0/).

> This file is regenerated from git history by running `make changelog` (uses [git-cliff](https://git-cliff.org/)).
> Do not edit it manually.

---

## XRD API version matrix

| Package | v1alpha1 | v1beta1 | v1 |
|---|---|---|---|
| gitea-user | ✓ introduced `v0.1.0` | — | — |
| gitea-org | ✓ introduced `v0.1.0` | — | — |
| gitea-team | ✓ introduced `v0.1.0` | — | — |
| gitea-repository | ✓ introduced `v0.1.0` | — | — |

Legend: ✓ = served and storage · (d) = deprecated, served only · — = not defined

---

## [Unreleased]

### Changed

- Migrated from kubebuilder Go controller to Crossplane v2 + provider-terraform architecture.
- Packages moved to `package/` directory (one sub-directory per Configuration package).
- Added `VERSIONS.yaml` for unified package and XRD API version tracking.
- Added `.pre-commit-config.yaml` with YAML lint, kubeconform, and crossplane build hooks.
- Added `cliff.toml` for automated changelog generation via `git-cliff`.

---

## [v0.1.0] — 2026-05-25

Initial release of the W'xOps Gitea management platform packages.

### Added

- `gitea-user` — `XGiteaUser` XRD `v1alpha1` + Composition (inline Terraform Workspace).
- `gitea-org` — `XGiteaOrg` XRD `v1alpha1` + Composition.
- `gitea-team` — `XGiteaTeam` XRD `v1alpha1` + Composition (includes membership reconciliation).
- `gitea-repository` — `XGiteaRepository` XRD `v1alpha1` + Composition.
- Shared providers manifest (`providers/`): `provider-terraform`, `function-patch-and-transform`, `function-go-templating`, `ProviderConfig`.
- Kustomize overlays: production (`package/kustomization.yaml`) and dev (`package/dev/kustomization.yaml`).
- Example XR YAML files under `examples/`.
- Gitea CI workflow `.gitea/workflows/publish-packages.yaml`: builds and pushes all packages on `v*` tag, auto-bumps `configuration.yaml`.

### XRD API versions introduced

| Resource | API Version | Kind | Scope |
|---|---|---|---|
| `xgiteausers.platform.wxops.cloud` | `v1alpha1` | `XGiteaUser` | Cluster |
| `xgiteaorgs.platform.wxops.cloud` | `v1alpha1` | `XGiteaOrg` | Cluster |
| `xgiteateams.platform.wxops.cloud` | `v1alpha1` | `XGiteaTeam` | Cluster |
| `xgitearepos.platform.wxops.cloud` | `v1alpha1` | `XGiteaRepository` | Cluster |

---

[Unreleased]: https://gitea.xeusnguyen.xyz/platform-team/wxops-core/compare/v0.1.0...HEAD
[v0.1.0]: https://gitea.xeusnguyen.xyz/platform-team/wxops-core/releases/tag/v0.1.0
