# Changelog

All notable changes to W'xOps Core packages are documented here.

Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
Versioning follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html).
Commit messages follow [Conventional Commits](https://www.conventionalcommits.org/en/v1.0.0/).

> This file is regenerated from git history by running `make changelog`.
> Do not edit it manually.

> Each release below links to a tag-pinned snapshot of [`docs/`](docs/)
> (API reference) and [`VERSIONS.yaml`](VERSIONS.yaml) as they existed at
> that tag — not the current `main`. Follow the links in-repo for the
> latest state.

---
## [0.2.4] — 2026-06-22

### Bug Fixes

- Patch the decision to provision database base on dxr and label ([`2b304fd`](https://gitea.xeusnguyen.xyz/platform-team/wxops-core/commit/2b304fdac1ff6b55d803b7dccf18bbaed4084b7a))



📖 [API reference](https://gitea.xeusnguyen.xyz/platform-team/wxops-core/src/tag/v0.2.4/docs) · [`VERSIONS.yaml`](https://gitea.xeusnguyen.xyz/platform-team/wxops-core/src/tag/v0.2.4/VERSIONS.yaml)
🔍 [Diff vs 0.2.3](https://gitea.xeusnguyen.xyz/platform-team/wxops-core/compare/v0.2.3...v0.2.4)
## [0.2.3] — 2026-06-22

### Chores

- Fix error version function extra resources and bump latest version for provider and function ([`80a7d99`](https://gitea.xeusnguyen.xyz/platform-team/wxops-core/commit/80a7d9907d5ef1b81359ad1491026226f6046fd2))



📖 [API reference](https://gitea.xeusnguyen.xyz/platform-team/wxops-core/src/tag/v0.2.3/docs) · [`VERSIONS.yaml`](https://gitea.xeusnguyen.xyz/platform-team/wxops-core/src/tag/v0.2.3/VERSIONS.yaml)
🔍 [Diff vs 0.2.2](https://gitea.xeusnguyen.xyz/platform-team/wxops-core/compare/v0.2.2...v0.2.3)
## [0.2.2] — 2026-06-21

### Features

- Dynamic set tier for database and platform database cluster for more usage to intent with shared or dedicated ([`82553f6`](https://gitea.xeusnguyen.xyz/platform-team/wxops-core/commit/82553f653007862b44c29418131042252bbc6719))



📖 [API reference](https://gitea.xeusnguyen.xyz/platform-team/wxops-core/src/tag/v0.2.2/docs) · [`VERSIONS.yaml`](https://gitea.xeusnguyen.xyz/platform-team/wxops-core/src/tag/v0.2.2/VERSIONS.yaml)
🔍 [Diff vs 0.2.1](https://gitea.xeusnguyen.xyz/platform-team/wxops-core/compare/v0.2.1...v0.2.2)
## [0.2.1] — 2026-06-16

### CI/CD

- **ci**: Correct the regenerate changelog and add ignore for git-cliff to see regenerate ([`3286b18`](https://gitea.xeusnguyen.xyz/platform-team/wxops-core/commit/3286b18ae9832a5ed4f3e2b5062ab56941aa1674))


### Chores

- Attaching namespace for tenant-app applied SSO ([`c9fbfbd`](https://gitea.xeusnguyen.xyz/platform-team/wxops-core/commit/c9fbfbd94b01972384a822c30c4bc8fec0b4a05c))
- Regenerate changelog ([`106841b`](https://gitea.xeusnguyen.xyz/platform-team/wxops-core/commit/106841b89abcef7cd81102f04f4099868b409f49))



📖 [API reference](https://gitea.xeusnguyen.xyz/platform-team/wxops-core/src/tag/v0.2.1/docs) · [`VERSIONS.yaml`](https://gitea.xeusnguyen.xyz/platform-team/wxops-core/src/tag/v0.2.1/VERSIONS.yaml)
🔍 [Diff vs 0.2.0](https://gitea.xeusnguyen.xyz/platform-team/wxops-core/compare/v0.2.0...v0.2.1)
## [0.2.0] — 2026-06-15

### CI/CD

- **ci**: Add configuration for release and bump new version on CI and Make Tools ([`dad65f0`](https://gitea.xeusnguyen.xyz/platform-team/wxops-core/commit/dad65f08e8e3cf570a7d67f8739e26095dffee23))
- **ci**: Add workflow for auto-update changelog.md ([`9470f73`](https://gitea.xeusnguyen.xyz/platform-team/wxops-core/commit/9470f73a7ab7fcdd393cad4564f3f1cc8d7fea8a))


### Features

- Release new XRDs for database and application ([`19b835c`](https://gitea.xeusnguyen.xyz/platform-team/wxops-core/commit/19b835c1664f820ea071210f06641b6ef5a8fd3b))



📖 [API reference](https://gitea.xeusnguyen.xyz/platform-team/wxops-core/src/tag/v0.2.0/docs) · [`VERSIONS.yaml`](https://gitea.xeusnguyen.xyz/platform-team/wxops-core/src/tag/v0.2.0/VERSIONS.yaml)
🔍 [Diff vs 0.1.1](https://gitea.xeusnguyen.xyz/platform-team/wxops-core/compare/v0.1.1...v0.2.0)


> ⚠️ **API version bump (0.1.1 → 0.2.0)** — major/minor change usually means a new or
> changed XRD API version (`spec.versions[]`). Check the diff above and
> [`VERSIONS.yaml`](https://gitea.xeusnguyen.xyz/platform-team/wxops-core/src/tag/v0.2.0/VERSIONS.yaml)
> for affected packages, and [`docs/`](https://gitea.xeusnguyen.xyz/platform-team/wxops-core/src/tag/v0.2.0/docs)
> for schema changes.
## [0.1.1] — 2026-05-30

### Bug Fixes

- Patch the broken ci by replacing python module instead sed command ([`970625d`](https://gitea.xeusnguyen.xyz/platform-team/wxops-core/commit/970625d741ba905056a29e6140f9f87d3a2688fe))


### CI/CD

- **ci**: Refactor release workflow for bumping version and enhance pre-commit ([`7921ce4`](https://gitea.xeusnguyen.xyz/platform-team/wxops-core/commit/7921ce4bf6a61ae70e9d416139142e4097046cd3))


### Chores

- Remove default version will lead to error release with make ([`8e967a2`](https://gitea.xeusnguyen.xyz/platform-team/wxops-core/commit/8e967a21d581c0d1d1104e9a48d107056b499dc3))
- Fix the release bypass pip install git-cliff without python3-venv ([`513d1a9`](https://gitea.xeusnguyen.xyz/platform-team/wxops-core/commit/513d1a9b2cf39b97181470c9db76ace1ab96d1f9))



📖 [API reference](https://gitea.xeusnguyen.xyz/platform-team/wxops-core/src/tag/v0.1.1/docs) · [`VERSIONS.yaml`](https://gitea.xeusnguyen.xyz/platform-team/wxops-core/src/tag/v0.1.1/VERSIONS.yaml)
🔍 [Diff vs 0.1.0](https://gitea.xeusnguyen.xyz/platform-team/wxops-core/compare/v0.1.0...v0.1.1)
## [0.1.0] — 2026-05-27

### Chores

- Fix the changelog release and automation write release-notes for new one releasing ([`a5b54f3`](https://gitea.xeusnguyen.xyz/platform-team/wxops-core/commit/a5b54f35e92eefb6f468c35866b144bd7254f6d9))
- Prevent error for running server-side crossplane ([`21b351d`](https://gitea.xeusnguyen.xyz/platform-team/wxops-core/commit/21b351d90211a407c8bf05c8cb89a71cfdd441d9))
- Change makefile for finalize the changelog workflow ([`eeca0a7`](https://gitea.xeusnguyen.xyz/platform-team/wxops-core/commit/eeca0a7f56c6a362042eb583461ee55ca65d4f41))
- Update and preview changelog and set the release v0.1.0 ([`4d7ffe6`](https://gitea.xeusnguyen.xyz/platform-team/wxops-core/commit/4d7ffe6c8564846f3cf121f72609de71b90126f6))


### Features

- Migrate core from kubebuilder into crossplane for W'xOps Controller Implementation ([`b2990b6`](https://gitea.xeusnguyen.xyz/platform-team/wxops-core/commit/b2990b6732e73e4cad31795757efdd72e2a061cc))
- Setup core wxops with kubebuilder to kick-off project ([`8e89719`](https://gitea.xeusnguyen.xyz/platform-team/wxops-core/commit/8e897194137dfc9cf2ead6d45f86646828b3517c))



📖 [API reference](https://gitea.xeusnguyen.xyz/platform-team/wxops-core/src/tag/v0.1.0/docs) · [`VERSIONS.yaml`](https://gitea.xeusnguyen.xyz/platform-team/wxops-core/src/tag/v0.1.0/VERSIONS.yaml)
---
[0.2.4]: https://gitea.xeusnguyen.xyz/platform-team/wxops-core/releases/tag/v0.2.4
[0.2.3]: https://gitea.xeusnguyen.xyz/platform-team/wxops-core/releases/tag/v0.2.3
[0.2.2]: https://gitea.xeusnguyen.xyz/platform-team/wxops-core/releases/tag/v0.2.2
[0.2.1]: https://gitea.xeusnguyen.xyz/platform-team/wxops-core/releases/tag/v0.2.1
[0.2.0]: https://gitea.xeusnguyen.xyz/platform-team/wxops-core/releases/tag/v0.2.0
[0.1.1]: https://gitea.xeusnguyen.xyz/platform-team/wxops-core/releases/tag/v0.1.1
[0.1.0]: https://gitea.xeusnguyen.xyz/platform-team/wxops-core/releases/tag/v0.1.0
[Unreleased]: https://gitea.xeusnguyen.xyz/platform-team/wxops-core/compare/v0.2.4...HEAD

