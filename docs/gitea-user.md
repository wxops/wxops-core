# XGiteaUser

Manages a single Gitea user lifecycle (create / update / delete).

| | |
|---|---|
| **Group** | `platform.wxops.cloud` |
| **Kind** | `XGiteaUser` |
| **Plural** | `xgiteausers` |
| **Scope** | `Cluster` |
| **API versions** | `v1alpha1` (served, storage) |
| **Package** | [`package/gitea-user/`](../package/gitea-user/) — see [`VERSIONS.yaml`](../VERSIONS.yaml) for the current package version |

## `spec.parameters`

| Field | Type | Required | Default | Description |
|---|---|---|---|---|
| `giteaUrl` | `string` | yes | | Base URL of the Gitea instance (e.g. `https://gitea.example.com`). |
| `insecure` | `boolean` | | `false` | Skip TLS verification. True only for local/dev instances. |
| `username` | `string` | yes | | Login username for the Gitea account. |
| `email` | `string` | yes | | Email address for the Gitea account. Gitea sends the welcome notification here. |
| `fullName` | `string` | | `""` | Display name shown in the Gitea UI. |
| `admin` | `boolean` | | `false` | Grant site administrator privileges. |
| `mustChangePassword` | `boolean` | | `true` | Require the user to set a new password on first login. Always recommended when `send_notification` is on, since the initial password is auto-generated. |
| `visibility` | `string` (`public`, `limited`, `private`) | | `"private"` | Account visibility level. A private user won't appear in the member list of an organization. |
| `passwordLength` | `integer` (16–128) | | `24` | Length of the auto-generated initial password. |
| `passwordSpecial` | `boolean` | | `true` | Include special characters in the auto-generated password. |
| `allowCreateOrganization` | `boolean` | | `false` | Allow the user to create organizations. |
| `credentialsSecretRef` | `object` | yes | | Secret holding the Gitea admin token in tfvars format: `gitea_token = "admin-api-token"`. No password field is needed — the initial user password is generated automatically and emailed to the user via Gitea SMTP. |
| `credentialsSecretRef.name` | `string` | yes | | Secret name. |
| `credentialsSecretRef.namespace` | `string` | yes | | Secret namespace. |

## Example

See [`examples/gitea-user/xr.yaml`](../examples/gitea-user/xr.yaml) and
[`examples/gitea-user/credentials-secret.yaml`](../examples/gitea-user/credentials-secret.yaml).
