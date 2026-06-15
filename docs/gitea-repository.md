# XGiteaRepository

Manages a Gitea repository owned by an organisation.

| | |
|---|---|
| **Group** | `platform.wxops.cloud` |
| **Kind** | `XGiteaRepository` |
| **Plural** | `xgitearepos` |
| **Scope** | `Cluster` |
| **API versions** | `v1alpha1` (served, storage) |
| **Package** | [`package/gitea-repository/`](../package/gitea-repository/) — see [`VERSIONS.yaml`](../VERSIONS.yaml) for the current package version |

## `spec.parameters`

| Field | Type | Required | Default | Description |
|---|---|---|---|---|
| `giteaUrl` | `string` | yes | | Base URL of the Gitea instance. |
| `insecure` | `boolean` | | `false` | Skip TLS verification. |
| `orgName` | `string` | yes | | Organization that owns the repository. |
| `repoName` | `string` | yes | | Repository name (immutable after creation). |
| `description` | `string` | | `""` | Repository description. |
| `private` | `boolean` | | `false` | Make the repository private. |
| `autoInit` | `boolean` | | `true` | Initialize the repository with a README. |
| `defaultBranch` | `string` | | `main` | Default branch name. |
| `hasIssues` | `boolean` | | `true` | Enable the issue tracker. |
| `hasWiki` | `boolean` | | `false` | Enable the wiki. |
| `hasProjects` | `boolean` | | `false` | Enable projects. |
| `hasPullRequests` | `boolean` | | `true` | Enable pull requests. |
| `credentialsSecretRef` | `object` | yes | | Secret holding the Gitea admin token in tfvars format: `gitea_token = "admin-token"`. |
| `credentialsSecretRef.name` | `string` | yes | | Secret name. |
| `credentialsSecretRef.namespace` | `string` | yes | | Secret namespace. |

## Example

See [`examples/gitea-repository/xr.yaml`](../examples/gitea-repository/xr.yaml).
