# XGiteaTeam

Manages a team inside a Gitea organisation, including membership.

| | |
|---|---|
| **Group** | `platform.wxops.cloud` |
| **Kind** | `XGiteaTeam` |
| **Plural** | `xgiteateams` |
| **Scope** | `Cluster` |
| **API versions** | `v1alpha1` (served, storage) |
| **Package** | [`package/gitea-team/`](../package/gitea-team/) — see [`VERSIONS.yaml`](../VERSIONS.yaml) for the current package version |

## `spec.parameters`

| Field | Type | Required | Default | Description |
|---|---|---|---|---|
| `giteaUrl` | `string` | yes | | Base URL of the Gitea instance. |
| `insecure` | `boolean` | | `false` | Skip TLS verification. |
| `orgName` | `string` | yes | | Name of the organization this team belongs to. |
| `teamName` | `string` | yes | | Team name within the organization. |
| `description` | `string` | | `""` | Team description. |
| `permission` | `string` (`none`, `read`, `write`, `admin`, `owner`) | | `read` | Base permission level for all team members. |
| `units` | `string` | | `"repo.code,repo.issues,repo.pulls"` | Comma-separated repository feature units the team has access to. Valid values: `repo.code`, `repo.issues`, `repo.ext_issues`, `repo.wiki`, `repo.pulls`, `repo.releases`, `repo.projects`, `repo.ext_wiki`. |
| `includeAllRepositories` | `boolean` | | `false` | Automatically grant access to all org repositories. |
| `canCreateRepos` | `boolean` | | `false` | Allow team members to create repositories in the org. |
| `members` | `string` | | `""` | Comma-separated list of Gitea usernames to add as team members. Membership is reconciled on every sync — removing a name removes the user from the team. Works for both managed and pre-existing users. |
| `credentialsSecretRef` | `object` | yes | | Secret holding the Gitea admin token in tfvars format: `gitea_token = "admin-token"`. |
| `credentialsSecretRef.name` | `string` | yes | | Secret name. |
| `credentialsSecretRef.namespace` | `string` | yes | | Secret namespace. |

## Example

See [`examples/gitea-team/xr.yaml`](../examples/gitea-team/xr.yaml).
