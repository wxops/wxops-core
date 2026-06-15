# XTenantDatabase

Tenant-facing PostgreSQL database on a platform cluster with Vault-backed
credentials and ESO sync.

| | |
|---|---|
| **Group** | `platform.wxops.cloud` |
| **Kind** | `XTenantDatabase` |
| **Plural** | `xtenantdatabases` |
| **Scope** | `Cluster` |
| **API versions** | `v1alpha1` (served, storage) |
| **Package** | [`package/tenant-database/`](../package/tenant-database/) — see [`VERSIONS.yaml`](../VERSIONS.yaml) for the current package version |
| **Composition function** | [`function-kcl`](https://github.com/crossplane-contrib/function-kcl) — see [`kcl/tenant-database/main.k`](../kcl/tenant-database/main.k) |

## `spec.parameters`

| Field | Type | Required | Default | Description |
|---|---|---|---|---|
| `tier` | `string` | | `"shared"` | Platform-defined cluster pool to provision this database on. Maps to a `clusterRef`/`clusterNamespace` via a platform-maintained lookup table (see [`kcl/tenant-database/main.k`](../kcl/tenant-database/main.k)). Ignored if `clusterRef`/`clusterNamespace` are set explicitly. Available tiers: `shared` → `cluster-a` / `cnpg-system`. |
| `clusterRef` | `string` | | | Name of the platform cluster to provision this database on. Must match the `clusterName` of an existing `XPlatformDatabaseCluster` (used as `spec.cluster.name` on the CNPG `Database` CR, and as the name of the per-cluster `postgresql.sql.crossplane.io` `ProviderConfig` — created by `platform-database-clusters` from its superuser secret — referenced by this tenant's `provider-sql` `Role`). Optional — defaults to the cluster mapped from `tier` if unset. |
| `clusterNamespace` | `string` | | | Kubernetes namespace where the CNPG cluster lives. All resources composed by this XR are created here (required for the CNPG `Database` CR, which is namespace-scoped to the cluster). Optional — defaults to the namespace mapped from `tier` if unset. |
| `dbName` | `string` | yes | | PostgreSQL database name to create. Must be unique per cluster. |
| `owner` | `string` | yes | | Team or project identifier (e.g. `"rocket-team"`). Used to scope the Vault path and PostgreSQL role name. |
| `extensions` | `array<string>` | | `[]` | PostgreSQL extensions to enable in the database. Example: `[uuid-ossp, pgcrypto, postgis]`. |
| `databaseReclaimPolicy` | `string` (`delete`, `retain`) | | `"retain"` | CNPG `Database.spec.databaseReclaimPolicy`. `"retain"` (default) protects this tenant's database from XR/claim deletion: the database and its owning role both survive XR deletion and must be cleaned up manually if the tenant is decommissioned. Set to `"delete"` to have CNPG drop the database on XR deletion (which also allows the owning role to be dropped) — a `ClusterUsage` (`tenant-role-db-usage`) orders this so the role's `DROP ROLE` runs only after the database's `DROP DATABASE` has completed, avoiding the `2BP01` ("role ... cannot be dropped because some objects depend on it") parallel-deletion race. Also controls the connection-creds Secret and the ExternalSecret/Password-generator that manage it: `"retain"` orphans them on XR deletion — the existing password is preserved and reused on recreate (an admin must delete them manually to force a new password); `"delete"` removes them along with everything else, so recreation generates a brand-new password. A second `ClusterUsage` (`tenant-conn-role-usage`) orders this: the connection-creds Secret's deletion is blocked until `DROP ROLE` has completed, then replayed — otherwise provider-sql's `Observe()` (which always reads the Role's `passwordSecretRef`, even while deleting) permanently fails once the Secret is gone, leaving the Role stuck in `Terminating` forever. |
| `vaultSecretStoreName` | `string` | | `"vault-cluster-store"` | Name of the ESO `ClusterSecretStore` used by the `PushSecret` that writes connection creds to Vault at `tenant/{owner}/{dbName}/connection-creds` (`refreshInterval: "0"` — pushed once on creation/spec-change, since the password never changes afterwards under `CreatedOnce`). Consuming that Vault entry into an app namespace (e.g. via an `ExternalSecret`) is a tenant/GitOps concern — see [`tenant-app`](./tenant-app.md)'s `secretsFrom.database` toggle — not handled by this XR. |

> **Password rotation** is intentionally not implemented: `provider-sql`'s `Role` reconciler only sets the role's password at `Create()` time and never re-applies changes on an existing role, so any rotation must also converge Postgres itself — a platform-level concern (e.g. Vault Database Secrets Engine dynamic/rotated roles), tracked separately in the backlog.

## Example

See [`examples/tenant-database/xr.yaml`](../examples/tenant-database/xr.yaml).
