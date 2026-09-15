# Setup — installing W'xOps Core on a cluster

> Install the shared providers once, give the Gitea packages their credentials, install the packages,
> then apply a first resource. For what each resource does once it exists, see the
> [API reference](../api-reference/README.md).

**Table of Contents**
- [Prerequisites](#prerequisites)
- [Platform dependencies, per package](#platform-dependencies-per-package)
- [1 — Install providers once per cluster](#1--install-providers-once-per-cluster)
- [2 — Create a credentials secret](#2--create-a-credentials-secret)
- [3 — Install packages](#3--install-packages)
- [4 — Apply a first resource](#4--apply-a-first-resource)
- [Uninstalling](#uninstalling)
- [Next](#next)

---

## Prerequisites

- The [`crossplane` CLI](https://docs.crossplane.io/latest/cli/), v2.3 or later
- `kubectl` pointed at a cluster with Crossplane v2.3 or later installed
- `pre-commit`, only if you will change this repository (see the
  [development guide](../development/README.md))

## Platform dependencies, per package

W'xOps Core composes resources that other operators reconcile. Install what the packages you use need:

| Package | Needs in the cluster |
|---|---|
| `gitea-user`, `gitea-org`, `gitea-team`, `gitea-repository` | A reachable Gitea instance and an admin token (step 2) |
| `platform-database-clusters` | CloudNativePG operator; External Secrets Operator with a Vault `ClusterSecretStore`; provider-sql (installed by step 1) |
| `tenant-database` | Everything `platform-database-clusters` needs, plus a cluster labelled for discovery; see [Required discovery labels](../api-reference/tenant-database.md#required-discovery-labels) |
| `tenant-app` | Only what the XR enables: cert-manager for `ingress.tls`, Traefik CRDs for `ingress`, Prometheus Operator CRDs for `monitoring`, Stakater Reloader for `reloader` |
| Darlane TTL enforcement (optional) | Kyverno, plus [`providers/policies/darlane-ttl.yaml`](../../providers/policies/darlane-ttl.yaml) |

## 1 — Install providers once per cluster

```bash
make providers
```

This applies everything in `providers/`: `provider-terraform`, `provider-kubernetes` (plus RBAC and a
`ProviderConfig`), `provider-sql`, `function-patch-and-transform`, `function-go-templating`,
`function-kcl`, `function-extra-resources`, and the Terraform `ProviderConfig`.

> [!NOTE]
> **`make providers` is required before `make install`.**
> - **Dependency names.** Crossplane's `dependsOn` in `crossplane.yaml` can auto-install missing
>   dependencies, but under long names derived from the OCI path (for example
>   `crossplane-contrib-function-kcl` instead of `function-kcl`). Compositions reference the short
>   names set by `providers/*.yaml`, so auto-installed dependencies are not found.
> - **Provider configuration.** Providers like `provider-kubernetes` also need a `RuntimeConfig`, RBAC
>   and a `ProviderConfig`, which `dependsOn` cannot provide.
>
> `dependsOn` is a **version-constraint safety net**, not an installer.

## 2 — Create a credentials secret

All Gitea packages use the same secret format:

```bash
kubectl create secret generic gitea-credentials \
  --from-literal=credentials='gitea_token = "your-admin-token"' \
  -n crossplane-system
```

For `gitea-user`, append a `password` field:

```bash
kubectl create secret generic gitea-credentials \
  --from-literal=credentials=$'gitea_token = "your-admin-token"\npassword = "initial-password"' \
  -n crossplane-system
```

## 3 — Install packages

**Production** — pulls the Configuration packages pinned in `package/install/` from the OCI registry:

```bash
make install
```

**Development** — applies XRDs and Compositions straight from this checkout, with no registry:

```bash
make install-dev
```

`make install-dev` is for a disposable development cluster only. Against a cluster that already runs
the packages, it overwrites package-managed XRDs and Compositions and skips every release gate.
Everything it applies carries `channel: nightly` (production packages ship `channel: stable`) — see
[Channels](../development/releasing.md#channels) for how an XR opts into either.

## 4 — Apply a first resource

```bash
kubectl apply -f examples/gitea-user/xr.yaml
kubectl get xgiteausers
kubectl describe xgiteauser <name>
crossplane resource trace xgiteauser <name>   # the XR and everything it composed
```

Wait for `status.created` and `status.ready`; see
[Reading status](../api-reference/README.md#reading-status).

## Uninstalling

```bash
make uninstall       # remove registry-installed Configuration packages
make uninstall-dev   # remove XRDs and Compositions applied by make install-dev
```

Delete XRs first, and read each Kind's deletion notes before you do. Kinds that hold data, like
`XTenantDatabase`, keep it by default.

## Next

- Ship an application end to end: [app onboarding](app-onboarding.md)
- Every Kind and what the reconcile loop does for it: [API reference](../api-reference/README.md)
- Build a portal on top: [portal integration](portal-integration.md)
