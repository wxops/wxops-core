# wxops-core-gitea-org

Crossplane Configuration package that manages a single Gitea organization lifecycle — create, update, and delete — through a Kubernetes-native XR claim.

Each `XGiteaOrg` claim maps to one `provider-terraform` Workspace that owns one `gitea_org` resource. This is the foundational unit of the W'xOps multi-tenant model: one organization per tenant.

## Prerequisites

Install these once per cluster before applying any claims:

```bash
kubectl apply -f providers/provider-terraform.yaml
kubectl apply -f providers/function-patch-and-transform.yaml
kubectl apply -f providers/providerconfig-terraform.yaml
```

## Install

### From a registry (GitOps)

Update `spec.package` in `configuration.yaml` to point to your published image, then apply:

```bash
kubectl apply -f package/gitea-org/configuration.yaml
```

### For development (direct apply)

```bash
kubectl apply -f package/gitea-org/xrd.yaml
kubectl apply -f package/gitea-org/composition.yaml
```

## Credentials secret

Create a Secret with the Gitea admin token in tfvars format:

```bash
kubectl create secret generic gitea-credentials \
  --from-literal=credentials='gitea_token = "your-admin-token"' \
  -n crossplane-system
```

This same secret can be reused for `XGiteaOrg`, `XGiteaTeam`, and `XGiteaRepository` claims.

## Usage

```yaml
apiVersion: platform.wxops.cloud/v1alpha1
kind: XGiteaOrg
metadata:
  name: team-alpha
spec:
  parameters:
    giteaUrl: https://gitea.example.com
    orgName: team-alpha
    fullName: Team Alpha
    description: Alpha product squad
    visibility: private
    credentialsSecretRef:
      name: gitea-credentials
      namespace: crossplane-system
```

See `examples/gitea-org/xr.yaml` for a working example.

## Relation to other packages

An organization is the root of the tenant hierarchy. Apply `XGiteaOrg` first, then `XGiteaTeam` and `XGiteaRepository` claims that reference the same `orgName`.

```
XGiteaOrg (team-alpha)
├── XGiteaTeam (team-alpha / backend)
├── XGiteaTeam (team-alpha / owners)
└── XGiteaRepository (team-alpha / api-service)
```

## Parameters

| Parameter | Type | Required | Default | Description |
|---|---|---|---|---|
| `giteaUrl` | string | yes | — | Base URL of the Gitea instance |
| `insecure` | bool | no | `false` | Skip TLS verification |
| `orgName` | string | yes | — | Organization login name (immutable after creation) |
| `fullName` | string | no | `""` | Display name in Gitea UI |
| `description` | string | no | `""` | Short description |
| `website` | string | no | `""` | Organization website URL |
| `location` | string | no | `""` | Location string |
| `visibility` | string | no | `public` | `public`, `limited`, or `private` |
| `credentialsSecretRef.name` | string | yes | — | Secret name |
| `credentialsSecretRef.namespace` | string | yes | — | Secret namespace |

## Build and publish

```bash
crossplane xpkg build \
  -f package/gitea-org \
  --name wxops-core-gitea-org

crossplane xpkg push \
  ghcr.io/wxops/wxops-core-gitea-org:v0.1.0 \
  -f wxops-core-gitea-org.xpkg
```
