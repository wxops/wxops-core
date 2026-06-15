# API Reference

Per-resource API reference for every XRD published by W'xOps Core. Each doc
covers the Kind, group/version, and `spec.parameters` schema as defined in
`package/<name>/xrd.yaml`.

| Doc | Kind | Package |
|---|---|---|
| [gitea-user](gitea-user.md) | `XGiteaUser` | [`package/gitea-user/`](../package/gitea-user/) |
| [gitea-org](gitea-org.md) | `XGiteaOrg` | [`package/gitea-org/`](../package/gitea-org/) |
| [gitea-team](gitea-team.md) | `XGiteaTeam` | [`package/gitea-team/`](../package/gitea-team/) |
| [gitea-repository](gitea-repository.md) | `XGiteaRepository` | [`package/gitea-repository/`](../package/gitea-repository/) |
| [platform-database-clusters](platform-database-clusters.md) | `XPlatformDatabaseCluster` | [`package/platform-database-clusters/`](../package/platform-database-clusters/) |
| [tenant-database](tenant-database.md) | `XTenantDatabase` | [`package/tenant-database/`](../package/tenant-database/) |
| [tenant-app](tenant-app.md) | `XTenantApp` | [`package/tenant-app/`](../package/tenant-app/) |
| [random-password](random-password.md) | `XRandomPassword` | [`package/random-password/`](../package/random-password/) |

For package/API version history see [`VERSIONS.yaml`](../VERSIONS.yaml). For
release notes see [`CHANGELOG.md`](../CHANGELOG.md) (generated via `make
changelog`).

## Guides

| Doc | Description |
|---|---|
| [app-onboarding](app-onboarding.md) | Golden path from picking a template to a running `tenant-app` — ties together the templates catalog, `gitea-repository`, and `tenant-app`. |
| [local-dev-tunneling](local-dev-tunneling.md) | Connecting Telepresence/Mirrord to a `tenant-app` namespace for live local development. |
