# ROADMAP

Status: `[ ]` open · `[~]` in progress · `[x]` shipped · `[-]` decided not to pursue

**Table of Contents**
- [ROADMAP](#roadmap)
  - [Shipped](#shipped)
    - [v0.1.0 / v0.1.1 - Gitea XRD Baseline](#v010--v011---gitea-xrd-baseline)
    - [v0.2.0 / v0.2.1 / v0.2.5 / v0.2.6 — XTenantApp baseline + SSO Middle Integration](#v020--v021--v025--v026--xtenantapp-baseline--sso-middle-integration)
    - [v0.2.2 / v0.2.4 — XTenantDatabase dynamic tier resolution](#v022--v024--xtenantdatabase-dynamic-tier-resolution)
    - [v0.2.7 — Gitea XRD additions](#v027--gitea-xrd-additions)
    - [v0.3.0 — Darlane + IngressRoute + KCL readiness fix](#v030--darlane--ingressroute--kcl-readiness-fix)
    - [v0.3.1 — Darlane header routing](#v031--darlane-header-routing)
  - [Active / Planned](#active--planned)
    - [Composition Lifecycle \& Breaking Change Safety](#composition-lifecycle--breaking-change-safety)
    - [Darlane — shipped in v0.3.0](#darlane--shipped-in-v030)
    - [Vault Database Secrets Engine (not started)](#vault-database-secrets-engine-not-started)
  - [Decided / out of scope](#decided--out-of-scope)

---

## Shipped

### v0.1.0 / v0.1.1 - Gitea XRD Baseline

- [x] Support 4 XR cluster scope, inc `gitea-org`, `gitea-repository`, `gitea-team` and `gitea-user`

### v0.2.0 / v0.2.1 / v0.2.5 / v0.2.6 — XTenantApp baseline + SSO Middle Integration

- [x] `ingress.className` default `traefik`
- [x] `envFrom[]`, `podAnnotations`, `reloader.enabled` (Stakater Reloader)
- [x] `appFlavor` label (`webapp`, `ai`, `ai-webapp`, `geo-webapp`, `search-webapp`)
- [x] `environment` label (`dev`/`staging`/`prod`) — pure metadata
- [x] `probes.{liveness,readiness,startup}` — golden-path `/healthz`/`/readyz` defaults
- [x] `darlane` debug-twin Deployment (`<appName>-darlane`, replicas 0, no Service/Ingress, shares env/envFrom)
- [x] Docs: Golden Path Contract
- [x] Support SSO Middileware reference using `traefik` with `cross-namespace` convention
- [x] Support ImagePullSecrets, ServiceAccount and Security Context. Also flag image string for easier updated by `kustomize`

### v0.2.2 / v0.2.4 — XTenantDatabase dynamic tier resolution

- [x] Replace hardcoded `_clusterTierMap` with dynamic discovery via `function-extra-resources`
- [x] `XPlatformDatabaseCluster.shared` toggle + `status` subresource for pool discovery
- [x] `tier: shared` — pool-based auto-assignment: least-loaded cluster, environment isolation, sticky assignment via status writeback
- [x] `tier: dedicated` — child `XPlatformDatabaseCluster` XR inline, sized via `dedicatedCluster` parameters
- [x] Vault path restructure: `{owner}/{dbName}/...` → `{owner}/databases/{dbName}/...`
- [x] Bug fixes (v0.2.4): extra-resources context key, unwrapped resources, `_get` guard, `matchLabels` required

### v0.2.7 — Gitea XRD additions

- [x] `gitea-user`: `allowCreateOrganization` boolean (default `false`)
- [x] `gitea-team`: `enableActions` / `actionsReadOnly` / `enablePackages` / `packagesReadOnly` via `null_resource` + Gitea API PATCH
- [x] `gitea-org`: `repoAdminChangeTeamAccess` boolean (default `false`)
- [x] Docs: updated parameters tables for all three XRDs

### v0.3.0 — Darlane + IngressRoute + KCL readiness fix

**`XTenantApp` — Darlane developer workspace**

- [x] `devSpace` renamed to `darlane` throughout XRD, KCL, and docs
- [x] `IngressRoute` (Traefik CRD) replaces standard Kubernetes `Ingress` for all apps — enables zero-downtime A/B weight switching without resource type changes
- [x] `ingress.tls.clusterIssuer` — auto-emits `cert-manager.io/v1 Certificate` CR; cert-manager provisions the TLS Secret into `tls.secretName`
- [x] `darlane.fileSync` — writable `emptyDir` volume at `mountPath`; `initContainer` pre-populates from image (`cp -rp /app/.`) including dotfiles; works with `readOnlyRootFilesystem: true`
- [x] `darlane.trafficWeight` (0–100) — Traefik `TraefikService` weighted split; `IngressRoute` backend switches in-place (same Object, no deletion gap)
- [x] `darlane.stickySession` — per-session cookie pinning on the weighted split
- [x] `darlane.telemetryPort` — dedicated `ClusterIP` Service for OTEL/Prometheus on the darlane pod
- [x] `darlane.productionOverride` + `darlane.ttl` — double opt-in gate for prod; Kyverno `ClusterCleanupPolicy` auto-scales down expired pods
- [x] `darlane.rbac` — scoped `Role`/`RoleBinding` for developer access to the darlane Deployment only
- [x] `darlane.serviceAccount` — dedicated SA with optional workload identity annotations
- [x] `volumes[]` and `darlane.volumes[]` expanded: `configMapName` and `secretName` sources alongside `claimName` (PVC); optional `items[]` key-to-path projections
- [x] provider-kubernetes RBAC: added `traefik.io` (IngressRoute, TraefikService) and `cert-manager.io` (Certificate) rules; retained `networking.k8s.io/ingresses` for migration

**KCL readiness fix — all packages**

- [x] `platform-database-clusters`: `_isReady` / `krm.kcl.dev/ready: "True"` applied to all composed `Object` resources — fixes Crossplane v2.3 + function-kcl v0.12.1 `type: Ready` always-False bug
- [x] `tenant-database`: same fix applied to all composed `Object` resources

### v0.3.1 — Darlane header routing

- [x] `darlane.headerRouting` — caller-controlled header pinning: a higher-priority `IngressRoute` rule routes requests carrying the configured header directly to darlane, bypassing `trafficWeight` and cookie assignment entirely
- [x] Composes freely with `trafficWeight` and `stickySession` — use `trafficWeight: 0` for pure explicit opt-in with no random traffic spill, or combine with a weighted canary for a developer/QA escape hatch alongside live A/B traffic
- [x] Darlane `ClusterIP` Service emitted whenever header routing is active, independent of `trafficWeight`

---

## Active / Planned

### Composition Lifecycle & Breaking Change Safety

Every composition update is immediately applied to **all** existing `XTenantApp` resources
(Crossplane default: `compositionUpdatePolicy: Automatic`). Most changes are additive and safe —
new optional fields with defaults pass through without touching existing resources. But some changes
are structurally breaking and can leave the entire fleet in a permanent reconciliation error state
with no easy recovery path.

The core failure mode: Kubernetes rejects in-place updates to immutable fields
(`Deployment.spec.selector`, PVC access modes, etc.). Crossplane's reconciliation loop enters a
permanent error and cannot self-heal — the old Deployment keeps running, but the XR is stuck and
any attempt to change it risks triggering a cascade delete of all composed resources (Deployment,
Service, Ingress), causing downtime. Recovery is manual and stressful under pressure.

**Phase 1 — classification & documentation**

- [ ] **Breaking change taxonomy** — formally classify every composition change type:
  - `safe` — additive: new optional fields, new composed resources with conditional emit,
    changes to pod template labels/annotations only
  - `careful` — in-place update: changes to resource spec fields (Crossplane patches the
    existing object; Kubernetes applies it). Risk depends on the field.
  - `breaking` — requires recreation: changes to `spec.selector` labels (Deployment),
    PVC access modes or storage class, `composition-resource-name` rename (delete + recreate),
    XRD field type change with pruning
  - Maintain a `BREAKING.md` section per package listing which changes fall in each tier.
    Commit authors must classify their change before merging.

- [ ] **Pre-flight check tool** — `make composition-diff` that compares the incoming
  composition against all live XR states and flags any immutable field conflict before apply.
  Catches selector label additions, resource renames, and type changes that would leave XRs stuck.

**Phase 2 — controlled rollout**

- [ ] **CompositionRevision channels** — label each published `CompositionRevision` with a
  `channel` (`stable` / `canary`). New XRs default to `stable`. Platform operators advance
  the channel label after validating canary. XRs with `compositionRevisionSelector:
  matchLabels: channel: stable` never receive breaking updates until explicitly migrated.
  CI publishes to `canary` first; promotion to `stable` is a manual gate.

- [ ] **Per-XR revision pinning in the portal** — surface `compositionRevisionRef` as a
  portal control so operators can pin individual apps to a known-good revision before a fleet
  update, then migrate one-by-one rather than all-at-once.

**Phase 3 — safe migration playbook for breaking changes**

- [ ] **Management policy escape hatch** — document and test the
  `managementPolicies: [Observe]` pattern: temporarily set an XR to `Observe`-only so
  Crossplane stops reconciling it, make the destructive change manually (delete Deployment,
  recreate with new selector), then restore `managementPolicies: [*]`. Prevents cascade
  delete while still allowing the operator to do the recreation in a controlled way.

- [ ] **Selector label freeze policy** — once an app is in `staging` or `prod`, the
  composition must never add a new label to `spec.selector.matchLabels`. New labels go to
  `spec.template.metadata.labels` only (pod labels, not selector labels). Enforce via a
  pre-commit check that diffs `selector.matchLabels` against the previous composition version.

- [ ] **Blue/green composition migration** — for fleet-wide breaking changes, a scripted
  path: scale up new Deployment (new selector) alongside old, shift Service selector, scale
  down old, patch XR to match new state. Crossplane then takes over managing the new
  Deployment. Avoids any downtime window.

- [ ] **Status subresource for migration state** — write `status.compositionMigration` to
  the XR during a managed migration: `pending | in-progress | complete | failed`. Portal
  can surface this as a banner so operators know which apps need action after a breaking
  composition release.

**Why this matters more than normal controller upgrades:** Crossplane compositions are applied
fleet-wide and immediately. A broken composition revision can affect every tenant app
simultaneously — not just new deployments. The blast radius is the entire platform, not one
service. Until Phase 1 (classification) is in place, treat every composition change to
`selector`-touching fields as a major version bump and coordinate with all teams before release.

---

### Darlane — shipped in v0.3.0

All core Darlane capabilities shipped in v0.2.x and v0.3.0. The `darlane.*` block
on `XTenantApp` is stable and complete. Further evolution moves to a standalone
`XDarlane` XRD — see [docs/darlane.md](docs/darlane.md#whats-next-xdarlane-xrd) for
the vision and architecture.

- [x] Tier 1: resources, securityContext, env overlay, args, fileSync
- [x] Tier 2: productionOverride, ttl, rbac, serviceAccount, Kyverno TTL enforcement
- [x] Traffic: trafficWeight, stickySession, headerRouting, telemetryPort, TraefikService A/B split
- [x] Volumes: PVC, ConfigMap, Secret with key-to-path projections
- [x] Docs: comprehensive guide at [docs/darlane.md](docs/darlane.md)

---

### Vault Database Secrets Engine (not started)

Dynamic credential management via Vault's Database Secrets Engine. Current static flow
(CNPG creates creds → ESO PushSecret → Vault KV2) remains the default; this layers on
top as an opt-in path.

- [ ] Design mount/path topology — single mount per cluster vs. per-tenant mounts. Key
  question: ESO reads once and fans out, or tenants read directly (each read generates a
  new lease)?
- [ ] `SecretBackendConnection` on `XPlatformDatabaseCluster` — per-cluster Vault
  connection with restricted PostgreSQL role (`CREATEROLE` only). Toggle:
  `vaultDatabaseBackend.enabled`.
- [ ] `SecretBackendRole` on `XTenantDatabase` — per-database dynamic credential
  template (creation/revocation SQL scoped to tenant's database).
- [ ] ESO lease lifecycle — `refreshInterval` triggers new leases; old ones get revoked.
  Different from current static flow where CNPG creds don't change unless manually rotated.
- [ ] Optional: compose `vault.vault.upbound.io/v1alpha1 Mount` on
  `XPlatformDatabaseCluster` (requires `provider-vault` install) so platform admins
  don't need to pre-create Vault mounts out-of-band.

---

## Decided / out of scope

These were evaluated and rejected. Don't re-litigate without new information.

- [-] **ArgoCD ApplicationSet (matrix generator: apps × environments)** — correct pattern
  for multi-env fan-out but lives in the GitOps repo, not here. `environment` label is
  `tenant-app`'s contribution to making it work.
- [-] **Kyverno for defaulting/mutating `XTenantApp`** — second source of truth alongside
  KCL Composition. Kyverno's place is validation/guardrails + `generate` policies keyed
  off `appFlavor`/`environment`, not defaulting.
- [-] **`partOf` label / `catalog-info.yaml` templates** — IDP/Backstage concern.
  `tenant-app` already provides the building blocks (`appName`, `environment`, `status.conditions`);
  the IDP layer consumes them. Revisit only if the IDP repo needs something `tenant-app`
  genuinely can't provide.
- [-] **`tenant-app` `databaseRef` for end-to-end credential wiring** — ExternalSecret is
  a GitOps/platform concern, provisioned separately. `tenant-app` stays focused on the
  workload; `tenant-database` on provisioning + Vault push. The bridging ExternalSecret
  is intentionally the platform layer's responsibility.
- [-] **Gateway API `HTTPRoute` as Ingress alternative** — real option, but a separate XRD
  (`XTenantHTTPRoute`), not a `tenant-app` field. Park until there's a concrete need
  (cross-namespace routing, traffic splitting) that Ingress can't satisfy.
- [-] **`platform-tenant`/`tenant-namespace` Crossplane package** — already covered by
  existing GitOps setup. Dual ownership with GitOps (two controllers reconciling the same
  `Namespace`/`RoleBinding`/`Quota`) is worse than the current pattern. Crossplane's value
  is dynamic parameterized resource graphs with cross-resource outputs, not static namespace
  scaffolding.
- [-] **`externalSecrets` / `database` toggles in `tenant-app`** — removed. `tenant-app`
  stays focused on `Deployment`/`Service`/`Ingress`/`darlane`. Vault-backed secrets and
  databases are provisioned separately and consumed via `envFrom.secretRef`.
- [-] **`Gitea-Team XRs`** - Not adopt **Matrix Permission** for setting up Gitea Team of Org
- [-] **Tunneling XRD block** - removed — mirrord CLI needs no manifest config
- [-] **debugPort, VS Code docs, Ephemeral DB branch, W'xOps CLI:** - moved to `XDarlane` XRD scope

