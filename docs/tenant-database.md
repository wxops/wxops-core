# XTenantDatabase

Tenant-facing PostgreSQL database with dynamic tier resolution (shared pool
auto-assign / dedicated cluster composition), Vault-backed credentials, and
ESO sync.

| | |
|---|---|
| **Group** | `platform.wxops.cloud` |
| **Kind** | `XTenantDatabase` |
| **Plural** | `xtenantdatabases` |
| **Scope** | `Cluster` |
| **API versions** | `v1alpha1` (served, storage) |
| **Package** | [`package/tenant-database/`](../package/tenant-database/) — see [`VERSIONS.yaml`](../VERSIONS.yaml) for the current package version |
| **Composition functions** | [`function-extra-resources`](https://github.com/crossplane-contrib/function-extra-resources) (shared cluster discovery) + [`function-kcl`](https://github.com/crossplane-contrib/function-kcl) — see [`kcl/tenant-database/main.k`](../kcl/tenant-database/main.k) |

## `spec.parameters`

### Tier resolution

| Field | Type | Required | Default | Description |
|---|---|---|---|---|
| `tier` | `string` (`shared`, `dedicated`) | | `"shared"` | **`shared`** — auto-assign to the least-loaded `XPlatformDatabaseCluster` labeled `shared: true` and matching this database's `environment`. The composition discovers shared clusters at render time via `function-extra-resources`, counts existing tenant databases per cluster, and picks the one with the fewest tenants. Prevents `dbName` collisions per cluster. The assignment is **sticky** — once resolved, subsequent reconciles reuse the same cluster. **`dedicated`** — compose a new `XPlatformDatabaseCluster` as a child resource (1 cluster = 1 database, fully isolated). Size the child cluster via `dedicatedCluster`. Ignored if `clusterRef`/`clusterNamespace` are set explicitly. |
| `environment` | `string` (`dev`, `staging`, `prod`) | | `"dev"` | Pool isolation: for `tier: shared`, the pool is filtered to clusters matching this environment. For `tier: dedicated`, passed through to the child cluster's `environment` field. |
| `dedicatedCluster` | `object` | | `{}` | Cluster sizing parameters when `tier` is `dedicated`. Ignored for `tier: shared` or when `clusterRef` is set explicitly. |
| `dedicatedCluster.instances` | `integer` (1–9) | | `1` | PostgreSQL instances. `1` = standalone, `3` = HA. |
| `dedicatedCluster.storageSize` | `string` | | `"8Gi"` | PVC storage size per instance. |
| `dedicatedCluster.postgresVersion` | `integer` | | `16` | PostgreSQL major version. |
| `dedicatedCluster.enablePooler` | `boolean` | | `true` | Deploy a PgBouncer RW pooler on the dedicated cluster. |
| `dedicatedCluster.namespace` | `string` | | `"cnpg-system"` | Namespace for the dedicated cluster. |
| `clusterRef` | `string` | | | Name of the platform cluster to provision this database on. Must match the `clusterName` of an existing `XPlatformDatabaseCluster`. When set (along with `clusterNamespace`), bypasses all tier logic. |
| `clusterNamespace` | `string` | | | Kubernetes namespace where the CNPG cluster lives. When set (along with `clusterRef`), bypasses all tier logic. |

### Database

| Field | Type | Required | Default | Description |
|---|---|---|---|---|
| `dbName` | `string` | yes | | PostgreSQL database name to create. Must be unique per cluster. |
| `owner` | `string` | yes | | Team or project identifier (e.g. `"rocket-team"`). Used to scope the Vault path and PostgreSQL role name. |
| `extensions` | `array<string>` | | `[]` | PostgreSQL extensions to enable in the database. Example: `[uuid-ossp, pgcrypto, postgis]`. |
| `databaseReclaimPolicy` | `string` (`delete`, `retain`) | | `"retain"` | CNPG `Database.spec.databaseReclaimPolicy`. `"retain"` (default) protects this tenant's database from XR/claim deletion: the database and its owning role both survive XR deletion and must be cleaned up manually if the tenant is decommissioned. Set to `"delete"` to have CNPG drop the database on XR deletion (which also allows the owning role to be dropped) — a `ClusterUsage` (`tenant-role-db-usage`) orders this so the role's `DROP ROLE` runs only after the database's `DROP DATABASE` has completed, avoiding the `2BP01` parallel-deletion race. Also controls the connection-creds Secret and its ExternalSecret/Password-generator: `"retain"` orphans them on XR deletion (existing password preserved); `"delete"` removes them (recreation generates a new password). A second `ClusterUsage` (`tenant-conn-role-usage`) orders connection-creds Secret deletion after `DROP ROLE` completes — otherwise provider-sql's `Observe()` deadlocks. |
| `vaultSecretStoreName` | `string` | | `"vault-cluster-store"` | Name of the ESO `ClusterSecretStore` used by the `PushSecret` that writes connection creds to Vault at `tenants/{owner}/databases/{dbName}/connection-creds`. The store is scoped to the `tenants/` KV mount, so the KCL code uses `{owner}/databases/{dbName}/connection-creds` as the `remoteKey` (same pattern as `platform-database-clusters` omitting `platform/`). Consuming that Vault entry into an app namespace is a tenant/GitOps concern — see [`tenant-app`](./tenant-app.md)'s `secretsFrom.database` toggle. |

> **Password rotation** is intentionally not implemented: `provider-sql`'s `Role` reconciler only sets the role's password at `Create()` time and never re-applies changes on an existing role, so any rotation must also converge Postgres itself — a platform-level concern (e.g. Vault Database Secrets Engine dynamic/rotated roles), tracked separately in the backlog.

## Examples

- [`examples/tenant-database/xr.yaml`](../examples/tenant-database/xr.yaml) — shared tier (default)
- [`examples/tenant-database/xr-dedicated.yaml`](../examples/tenant-database/xr-dedicated.yaml) — dedicated tier
