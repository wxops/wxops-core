# platform-wxops-tenant-database

Crossplane Configuration package that provisions a tenant-facing PostgreSQL
database on a platform [`XPlatformDatabaseCluster`](../platform-database-clusters/),
with a continuously reconciled `provider-sql` `Role` and Vault-backed
connection credentials synced via ESO.

Each `XTenantDatabase` claim maps to a CNPG `Database` CR + a `provider-sql`
`Role` + a `PushSecret` that writes connection creds to Vault at
`tenant/{owner}/{dbName}/connection-creds`. Composition logic is written in
KCL — see [`kcl/tenant-database/main.k`](../../kcl/tenant-database/main.k).

## Prerequisites

Install once per cluster (`make providers`):

```bash
kubectl apply -f providers/provider-kubernetes.yaml
kubectl apply -f providers/rbac-provider-kubernetes.yaml
kubectl apply -f providers/runtimeconfig-provider-kubernetes.yaml
kubectl apply -f providers/providerconfig-kubernetes.yaml
kubectl apply -f providers/provider-sql.yaml
kubectl apply -f providers/function-kcl.yaml
```

Also requires at least one [`XPlatformDatabaseCluster`](../platform-database-clusters/)
to exist (or the `tier` default `shared` → `cluster-a`/`cnpg-system` mapping
to resolve to a real cluster).

## Install

**Production** (registry):

```bash
kubectl apply -f package/install/tenant-database.yaml
```

**Development** (direct apply):

```bash
kubectl apply -k package/tenant-database/
```

## Usage

```yaml
apiVersion: platform.wxops.cloud/v1alpha1
kind: XTenantDatabase
metadata:
  name: rocket-team-payment-db
spec:
  parameters:
    # tier: shared   # default — maps to clusterRef: cluster-a, clusterNamespace: cnpg-system
    dbName: payment-db
    owner: rocket-team
    extensions:
      - uuid-ossp
      - pgcrypto
```

See [`examples/tenant-database/xr.yaml`](../../examples/tenant-database/xr.yaml)
for the full set of optional fields, and
[`docs/tenant-database.md`](../../docs/tenant-database.md) for the complete
`spec.parameters` reference (including `databaseReclaimPolicy` semantics).

## Relation to other packages

```
XPlatformDatabaseCluster (cluster-a)
└── XTenantDatabase (rocket-team / payment-db)
    └── tenant-app's secretsFrom.database  ← consumes the connection-creds Secret
```
