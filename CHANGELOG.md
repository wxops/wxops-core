# Changelog

All notable changes to W'xOps Core packages are documented here.

Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
Versioning follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html).
Commit messages follow [Conventional Commits](https://www.conventionalcommits.org/en/v1.0.0/).

> This file is regenerated from git history by running `make changelog`.
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
## [0.1.0] — 2026-05-27

### Chores

- Fix the changelog release and automation write release-notes for new one releasing ([`3d4f926`](3d4f92652d3db595ae00e4c424c54bcfd74f4b28))
- Prevent error for running server-side crossplane ([`21b351d`](21b351d90211a407c8bf05c8cb89a71cfdd441d9))
- Change makefile for finalize the changelog workflow ([`eeca0a7`](eeca0a7f56c6a362042eb583461ee55ca65d4f41))
- Update and preview changelog and set the release v0.1.0 ([`4d7ffe6`](4d7ffe6c8564846f3cf121f72609de71b90126f6))


### Features

- Migrate core from kubebuilder into crossplane for W'xOps Controller Implementation ([`b2990b6`](b2990b6732e73e4cad31795757efdd72e2a061cc))
- Setup core wxops with kubebuilder to kick-off project ([`8e89719`](8e897194137dfc9cf2ead6d45f86646828b3517c))

---
[0.1.0]: https://gitea.xeusnguyen.xyz/platform-team/wxops-core/releases/tag/v0.1.0
[Unreleased]: https://gitea.xeusnguyen.xyz/platform-team/wxops-core/compare/v0.1.0...HEAD
