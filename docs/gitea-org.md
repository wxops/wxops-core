# XGiteaOrg

Manages a Gitea organisation with visibility and metadata.

| | |
|---|---|
| **Group** | `platform.wxops.cloud` |
| **Kind** | `XGiteaOrg` |
| **Plural** | `xgiteaorgs` |
| **Scope** | `Cluster` |
| **API versions** | `v1alpha1` (served, storage) |
| **Package** | [`package/gitea-org/`](../package/gitea-org/) — see [`VERSIONS.yaml`](../VERSIONS.yaml) for the current package version |

## `spec.parameters`

| Field | Type | Required | Default | Description |
|---|---|---|---|---|
| `giteaUrl` | `string` | yes | | Base URL of the Gitea instance (e.g. `https://gitea.example.com`). |
| `insecure` | `boolean` | | `false` | Skip TLS verification. True only for local/dev instances. |
| `orgName` | `string` | yes | | Gitea organization login name (immutable after creation). |
| `fullName` | `string` | | `""` | Display name shown in the Gitea UI. |
| `description` | `string` | | `""` | Organization description. |
| `website` | `string` | | `""` | Organization website URL. |
| `location` | `string` | | `""` | Organization location. |
| `visibility` | `string` (`public`, `limited`, `private`) | | `public` | Organization visibility. |
| `credentialsSecretRef` | `object` | yes | | Secret holding the Gitea admin token in tfvars format: `gitea_token = "admin-token"`. |
| `credentialsSecretRef.name` | `string` | yes | | Secret name. |
| `credentialsSecretRef.namespace` | `string` | yes | | Secret namespace. |

## Example

See [`examples/gitea-org/xr.yaml`](../examples/gitea-org/xr.yaml).
