# XTenantApp

Tenant application scaffold — provisions a `Deployment` + `Service` +
optional `Ingress` + optional `ServiceAccount` for an application workload, following the
`app.kubernetes.io/*` label conventions used by the Kubewekend and Bitnami
Helm "common" libraries (`app.kubernetes.io/name`, `app.kubernetes.io/instance`,
`app.kubernetes.io/managed-by: crossplane`).

This XR deliberately stops at the application workload. Vault-backed secrets
(`ExternalSecret`/`PushSecret`) and databases ([`XTenantDatabase`](tenant-database.md))
are platform-level concerns wired up separately — point `envFrom` at the
Secret(s) they produce.

| | |
|---|---|
| **Group** | `platform.wxops.cloud` |
| **Kind** | `XTenantApp` |
| **Plural** | `xtenantapps` |
| **Scope** | `Cluster` |
| **API versions** | `v1alpha1` (served, storage) |
| **Package** | [`package/tenant-app/`](../package/tenant-app/) — see [`VERSIONS.yaml`](../VERSIONS.yaml) for the current package version |
| **Composition function** | [`function-kcl`](https://github.com/crossplane-contrib/function-kcl) — see [`kcl/tenant-app/main.k`](../kcl/tenant-app/main.k) |

## `spec.parameters`

### Core

| Field | Type | Required | Default | Description |
|---|---|---|---|---|
| `appName` | `string` | yes | | Application name. Used as the name of the `Deployment`/`Service`/`Ingress` and as the value of the `app.kubernetes.io/name` and `app.kubernetes.io/instance` labels. |
| `namespace` | `string` | yes | | Target namespace for all resources created by this XR. |
| `environment` | `string` | | `"dev"` | One of `dev`, `staging`, `prod`. Applied as the `wxops.cloud/environment` label on created resources — purely metadata for dashboards, cost reports, and Kyverno generate-policies. Pairs with an ArgoCD ApplicationSet matrix generator (apps × environments). |
| `appFlavor` | `string` | | `"webapp"` | One of `webapp`, `ai`, `ai-webapp`, `geo-webapp`, `search-webapp`. Applied as the `wxops.cloud/app-flavor` label on created resources — purely metadata for platform-level automation (e.g. a separate `XTenantDatabase` claim choosing `pgvector`/`postgis` extensions, or Kyverno generate-policies) to key off. Does not affect any resource composed by this XR. |
| `templateId` | `string` | | | Backstage/IDP software-template identifier this app was scaffolded from. Applied as the `wxops.cloud/template-id` annotation on all composed resources — catalog-linking metadata only. |
| `repository.url` | `string` | | | URL of the application's source repository (e.g. a Gitea repo created or imported by the platform/portal — `tenant-app` doesn't manage repositories). Applied as the `wxops.cloud/repo-url` annotation on all composed resources. |
| `image` | `string` | yes | | Container image reference (`repository:tag`). e.g. `ghcr.io/org/app:1.0.0`. Use this single-string form so Kustomize image-updater can target it directly. |
| `imagePullPolicy` | `string` | | `"IfNotPresent"` | One of `Always`, `IfNotPresent`, `Never`. |
| `imagePullSecrets` | `array<string>` | | `[]` | Names of existing Secrets (type `kubernetes.io/dockerconfigjson`) for pulling from private registries. Added to `spec.imagePullSecrets` on both the main Deployment and devSpace. The Secrets must already exist in the target namespace — this XR does not create them. |
| `replicas` | `integer` | | `1` | |
| `containerPort` | `integer` | | `8080` | |
| `terminationGracePeriodSeconds` | `integer` | | `30` | Seconds to wait for graceful shutdown after SIGTERM before SIGKILL. Increase for apps with long-running requests, connection draining, or batch processing. |
| `resources` | `object` | | | Passed through verbatim to the container's `resources` field (`requests`/`limits` × `cpu`/`memory`). |
| `env` | `array<{name, value}>` | | `[]` | Plain (non-secret) environment variables. |
| `envFrom` | `array<{secretRef\|configMapRef: {name}}>` | | `[]` | Additional `envFrom` sources, merged after the `secretsFrom.{app,database}`-managed `secretRef`s (if enabled). |
| `podAnnotations` | `object<string, string>` | | `{}` | Annotations applied to the pod template (e.g. for Prometheus scraping). |
| `deploymentAnnotations` | `object<string, string>` | | `{}` | Extra annotations merged onto the main `Deployment`'s `metadata.annotations`, alongside `wxops.cloud/template-id`, `wxops.cloud/repo-url`, and (if `reloader.enabled`) `reloader.stakater.com/auto`. |
| `labels` | `object<string, string>` | | `{}` | Extra labels merged onto all composed resources (`Deployment`, `devSpace`, `Service`, `Ingress`, `ServiceAccount`). The standard `app.kubernetes.io/*` and `wxops.cloud/*` labels always take precedence — they cannot be overridden, since selectors depend on them. |
| `command` | `array<string>` | | | Optional container command override. |
| `args` | `array<string>` | | | Optional container args override. |

### `rolloutStrategy`

`Deployment.spec.strategy` — how Pods are replaced on update, relevant when
`replicas > 1`.

| Field | Type | Default | Description |
|---|---|---|---|
| `rolloutStrategy.type` | `string` | `"RollingUpdate"` | One of `RollingUpdate`, `Recreate`. |
| `rolloutStrategy.rollingUpdate.maxSurge` | `string\|integer` | `"25%"` | Only used when `type` is `RollingUpdate`. |
| `rolloutStrategy.rollingUpdate.maxUnavailable` | `string\|integer` | `"25%"` | Only used when `type` is `RollingUpdate`. |

### `serviceAccount`

| Field | Type | Default | Description |
|---|---|---|---|
| `serviceAccount.create` | `boolean` | `false` | If true, compose a new `ServiceAccount` in the target namespace. |
| `serviceAccount.name` | `string` | `appName` (when `create: true`) | ServiceAccount name. When `create: false`, must reference an existing SA in the target namespace. If the entire `serviceAccount` section is omitted, the namespace default SA is used. |
| `serviceAccount.annotations` | `object<string, string>` | `{}` | Annotations on the created SA (ignored when `create: false`). Use for workload identity bindings — e.g. `eks.amazonaws.com/role-arn` (IRSA), `iam.gke.io/gcp-service-account` (GCP WI). |

### `securityContext`

Pod-level and container-level security settings. Pod-level fields apply to
all containers; container-level fields apply to the main app container (and
devSpace container if enabled).

| Field | Type | Default | Description |
|---|---|---|---|
| `securityContext.runAsNonRoot` | `boolean` | | Pod-level. Require all containers to run as non-root. Many clusters enforce this via admission policies. |
| `securityContext.runAsUser` | `integer` | | Pod-level. UID to run all containers as. |
| `securityContext.runAsGroup` | `integer` | | Pod-level. Primary GID for all containers. |
| `securityContext.fsGroup` | `integer` | | Pod-level. GID applied to all mounted volumes. |
| `securityContext.readOnlyRootFilesystem` | `boolean` | | Container-level. Mount the root filesystem as read-only. |
| `securityContext.allowPrivilegeEscalation` | `boolean` | | Container-level. Whether the process can gain more privileges than its parent. Set to `false` for hardened workloads. |
| `securityContext.capabilities.drop` | `array<string>` | `[]` | Container-level. Capabilities to drop. Use `["ALL"]` to drop all (recommended baseline). |
| `securityContext.capabilities.add` | `array<string>` | `[]` | Container-level. Capabilities to add back (e.g. `["NET_BIND_SERVICE"]`). |

### `secretsFrom`

Toggles for `envFrom.secretRef` entries pointing at Secrets provisioned
out-of-band by the platform/GitOps. This XR only wires the reference by
name — it does not provision or wait for the Secret to exist (the
Deployment will fail to start until it's created).

| Field | Type | Default | Description |
|---|---|---|---|
| `secretsFrom.app.enabled` | `boolean` | `false` | If true, adds a `secretRef` to `secretsFrom.app.secretName` — e.g. the Secret a platform-managed `ExternalSecret`/`PushSecret` writes app secrets from Vault into. |
| `secretsFrom.app.secretName` | `string` | `"{appName}-env"` | |
| `secretsFrom.database.enabled` | `boolean` | `false` | If true, adds a `secretRef` to `secretsFrom.database.secretName` — e.g. a platform-provisioned [`XTenantDatabase`](tenant-database.md)'s connection-creds Secret. |
| `secretsFrom.database.secretName` | `string` | `"{appName}-db-creds"` | |

### `reloader` ([Stakater Reloader](https://github.com/stakater/Reloader))

| Field | Type | Default | Description |
|---|---|---|---|
| `reloader.enabled` | `boolean` | `false` | If true, adds `reloader.stakater.com/auto: "true"` to the `Deployment`'s annotations, triggering a rolling restart via the Reloader controller when referenced ConfigMaps/Secrets change. Requires Reloader installed in-cluster. |

### `devSpace` (debug "twin" Deployment)

If enabled, a second `<appName>-dev` Deployment is created alongside the
main one — same `image`/`env`/`envFrom`, scaled to `0` by default and with
**no `Service`/`Ingress` of its own** (zero external exposure). Scale it up
on-demand and point Telepresence/Mirrord at
`deployment/<appName>-dev` to debug with the same environment as production
— see [local-dev-tunneling.md](local-dev-tunneling.md).

| Field | Type | Default | Description |
|---|---|---|---|
| `devSpace.enabled` | `boolean` | `false` | |
| `devSpace.replicas` | `integer` | `0` | Scale to `1` on-demand to start the debug pod. |
| `devSpace.image` | `string` | main `image` | Optional image override (`repository:tag`). e.g. `ghcr.io/org/app:debug`. Defaults to the main image. |
| `devSpace.command` | `array<string>` | `["sleep", "infinity"]` | Keeps the pod alive for `kubectl exec`/port-forward without serving traffic itself. |

### `service`

| Field | Type | Default | Description |
|---|---|---|---|
| `service.enabled` | `boolean` | `true` | |
| `service.type` | `string` | `"ClusterIP"` | One of `ClusterIP`, `NodePort`, `LoadBalancer`. |
| `service.port` | `integer` | `80` | Service port. `targetPort` is always `containerPort`. |

### `probes`

HTTP GET liveness/readiness/startup probes against `containerPort`.
`liveness`/`readiness` default to **enabled**, mirroring `service.enabled` —
apps without a `Service` (e.g. background workers) default to no probes but
can opt in explicitly.

| Field | Type | Default | Description |
|---|---|---|---|
| `probes.liveness.enabled` | `boolean` | `service.enabled` | |
| `probes.liveness.path` | `string` | `"/healthz"` | |
| `probes.liveness.port` | `integer` | `containerPort` | |
| `probes.liveness.initialDelaySeconds` | `integer` | `10` | |
| `probes.liveness.periodSeconds` | `integer` | `10` | |
| `probes.liveness.timeoutSeconds` | `integer` | `1` | |
| `probes.liveness.failureThreshold` | `integer` | `3` | |
| `probes.readiness.enabled` | `boolean` | `service.enabled` | |
| `probes.readiness.path` | `string` | `"/readyz"` | |
| `probes.readiness.port` | `integer` | `containerPort` | |
| `probes.readiness.initialDelaySeconds` | `integer` | `5` | |
| `probes.readiness.periodSeconds` | `integer` | `10` | |
| `probes.readiness.timeoutSeconds` | `integer` | `1` | |
| `probes.readiness.failureThreshold` | `integer` | `3` | |
| `probes.startup.enabled` | `boolean` | `false` | If enabled, gates liveness/readiness until the first successful check — useful for slow-starting apps. |
| `probes.startup.path` | `string` | `"/healthz"` | |
| `probes.startup.port` | `integer` | `containerPort` | |
| `probes.startup.periodSeconds` | `integer` | `10` | |
| `probes.startup.failureThreshold` | `integer` | `30` | |

### `ingress`

| Field | Type | Default | Description |
|---|---|---|---|
| `ingress.enabled` | `boolean` | `false` | |
| `ingress.className` | `string` | `"traefik"` | |
| `ingress.host` | `string` | | **Required if `ingress.enabled`** (validated by the Composition, not the XRD schema). |
| `ingress.path` | `string` | `"/"` | |
| `ingress.pathType` | `string` | `"Prefix"` | One of `Prefix`, `Exact`, `ImplementationSpecific`. |
| `ingress.annotations` | `object<string, string>` | `{}` | |
| `ingress.tls.enabled` | `boolean` | `false` | |
| `ingress.tls.secretName` | `string` | `"{appName}-tls"` | |
| `ingress.tls.clusterIssuer` | `string` | | Optional. If set (and `tls.enabled`), adds the `cert-manager.io/cluster-issuer` annotation so cert-manager automatically requests a certificate into `tls.secretName`. Requires [cert-manager](https://cert-manager.io/) and the named `ClusterIssuer` to exist in-cluster. If unset, `tls.secretName` must be provisioned by some other means (e.g. a pre-existing wildcard cert Secret). |
| `ingress.auth.enabled` | `boolean` | `false` | If true, adds the `traefik.ingress.kubernetes.io/router.middlewares` annotation referencing `kube-system-auth-errors@kubernetescrd` and `kube-system-forward-auth-redirect@kubernetescrd` — SSO via oauth2-proxy's ForwardAuth, with a redirect to the login page on `401`. See [SSO via oauth2-proxy](#sso-via-oauth2-proxy) below. |

#### SSO via oauth2-proxy

When `ingress.auth.enabled: true`, Traefik runs the `auth-errors` and
`forward-auth-redirect` middlewares before routing to this app — together
they call oauth2-proxy's ForwardAuth endpoint and redirect unauthenticated
users (`401`) to the login page.

Both `Middleware` CRDs are expected to exist in the `kube-system` namespace.
`tenant-app` references them cross-namespace using the
`kube-system-<name>@kubernetescrd` convention (e.g.
`kube-system-auth-errors@kubernetescrd`). This requires Traefik to be
configured with `--providers.kubernetescrd.allowCrossNamespace=true`.
`tenant-app` does not provision or manage these `Middleware` CRDs.

## Vault secrets & databases

`tenant-app` does not provision Vault-backed secrets or databases itself.
Environment variables sourced from Vault (`ExternalSecret`/`PushSecret`) and
tenant databases ([`XTenantDatabase`](tenant-database.md)) are provisioned
separately at the platform level. Reference the resulting Kubernetes
`Secret`(s) via [`secretsFrom`](#secretsfrom) (simple enable + default
naming convention):

```yaml
secretsFrom:
  app:
    enabled: true        # adds envFrom.secretRef: payment-api-env
  database:
    enabled: true        # adds envFrom.secretRef: payment-api-db-creds
```

or via `envFrom` directly for any other Secret/ConfigMap name.

> **Go-live ordering contract**: `tenant-app` does not wait for or validate
> that `secretsFrom.{app,database}.secretName` exist — it only adds
> `envFrom.secretRef` entries by name. The referenced Secret(s) **must be
> created before (or alongside) this XR**, or the Deployment's Pods will
> fail to start (`CreateContainerConfigError: secret "..." not found`).
> This is the platform/GitOps's responsibility — when enabling
> `secretsFrom`, make sure the corresponding `ExternalSecret`/`PushSecret`/
> `XTenantDatabase` is applied first.

`appFlavor` remains purely a label (`wxops.cloud/app-flavor`) for portal
filtering and platform automation — e.g. the portal/platform layer can use it
to pick `pgvector`/`postgis`/etc. extensions when provisioning a database for
this app, without `tenant-app` itself knowing anything about databases.

## Golden Path Contract

`tenant-app` defaults `probes.liveness` and `probes.readiness` to **enabled**
whenever `service.enabled` is true (the default), targeting:

- `GET /healthz` — liveness
- `GET /readyz` — readiness

This is a *contract*, not something the Composition can enforce: if your
application doesn't expose these two HTTP endpoints on `containerPort`, the
Deployment will fail to become ready (`readinessProbe` failures) or be
restarted in a loop (`livenessProbe` failures).

Two ways to satisfy the contract:

1. **Implement `/healthz` and `/readyz`** in your app (recommended — most
   frameworks provide this for free, e.g. Spring Boot Actuator
   `/actuator/health/liveness|readiness`, FastAPI/Express health-check
   middleware). This is expected to be baked into the language/framework
   scaffolds used to bootstrap new services (Backstage software templates),
   so a service created from a golden-path template already satisfies this
   out of the box.
2. **Override the paths** via `probes.liveness.path` /
   `probes.readiness.path` (or `probes.<liveness|readiness>.enabled: false`
   to disable a probe entirely) if your app uses different conventions or
   doesn't serve HTTP at all (e.g. `service.enabled: false` workers default
   to no probes).

`probes.startup` remains opt-in (`enabled: false` by default) for
slow-starting apps that need extra grace before liveness/readiness probes
begin counting failures.

## Example

See [`examples/tenant-app/xr.yaml`](../examples/tenant-app/xr.yaml).

## See also

- [Local dev tunneling (Telepresence / Mirrord)](local-dev-tunneling.md) —
  how to connect your local dev environment to a `tenant-app`'s namespace
  for live-coding against shared cluster resources.
