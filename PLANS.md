# PLANS.md

Working notes on ideas discussed but not (yet) implemented, plus the
reasoning behind decisions already made. This is a planning/context doc for
future sessions — not user-facing documentation (see `docs/` and
`release-notes/` for that).

Status legend: `[ ]` open / not started · `[~]` partially done · `[x]` done
· `[-]` decided not to pursue (with reason).

---

## `XTenantApp` — shipped in v0.2.0

- [x] `ingress.className` default `traefik`.
- [x] `envFrom[]`, `podAnnotations`, `reloader.enabled` (Stakater Reloader).
- [x] `appFlavor` (`webapp`, `ai`, `ai-webapp`, `geo-webapp`,
      `search-webapp`) — `wxops.cloud/app-flavor` label only.
- [x] `environment` label (`dev`/`staging`/`prod`) — pure metadata.
- [x] `probes.{liveness,readiness,startup}` — golden-path `/healthz`
      `/readyz` defaults, enabled when `service.enabled`.
- [x] `devSpace` debug-twin Deployment (`<appName>-dev`, replicas 0, no
      Service/Ingress, shares env/envFrom).
- [x] Docs: Golden Path Contract, local-dev-tunneling guide.

---

## `XTenantApp` — `externalSecrets`/`database` toggles removed

Previously, `tenant-app` had `externalSecrets` (ESO `ExternalSecret` →
envFrom) and `database` (composed `XTenantDatabase`) toggles, with
`appFlavor` driving `database.extensions` defaults.

Decision: **removed both**. `tenant-app` should stay focused on the
application workload (`Deployment`/`Service`/`Ingress`/`devSpace`) only.
Vault-backed secrets and databases are platform-level concerns, provisioned
separately (portal/GitOps) and consumed via `envFrom.secretRef` —
`tenant-app` doesn't need to know how those Secrets were produced.

`appFlavor` stays as a pure `wxops.cloud/app-flavor` label — the
portal/platform layer reads it to decide things like which Postgres
extensions (`pgvector`/`postgis`/...) to enable when it provisions a
database for this app, but `tenant-app` itself has zero database-awareness.

---

## Decided / out of scope (don't re-litigate without new info)

- [-] **ArgoCD ApplicationSet (matrix generator: apps × environments)** —
  correct pattern for multi-env fan-out, but lives in the GitOps repo, not
  this Composition. `environment` label is `tenant-app`'s contribution to
  making this work.
- [-] **Kyverno for defaulting/mutating `XTenantApp`** — would create a
  second source of truth alongside the KCL Composition. Kyverno's place is
  validation/guardrails + `generate` policies (NetworkPolicy, ResourceQuota
  keyed off `wxops.cloud/app-flavor`/`environment`), not defaulting.
- [-] **`partOf`/`app.kubernetes.io/part-of` label + catalog-info.yaml
  templates** — IDP/Backstage-repo concern. `tenant-app` already guarantees
  the building blocks (`appName` consistency, `environment` label,
  `status.conditions`); the catalog/IDP layer consumes them. Revisit only if
  the IDP repo needs something `tenant-app` *can't* currently provide.
- [-] **Gateway API `HTTPRoute` as Ingress alternative** — real option, but
  a separate XRD (e.g. `XTenantHTTPRoute`), not a `tenant-app` field. Park
  until there's a concrete need (e.g. cross-namespace routing, traffic
  splitting) that Ingress can't satisfy.
- [-] **`platform-tenant`/`tenant-namespace` Crossplane package** (Namespace +
  RBAC + ResourceQuota/policies bootstrap per tenant) — already covered by
  the existing GitOps setup. Adding a Crossplane XR for the same static,
  rarely-changing resources would create dual ownership/drift with GitOps
  (two controllers reconciling the same `Namespace`/`RoleBinding`/`Quota`
  objects). Crossplane's value here is dynamic, parameterized resource
  graphs with cross-resource outputs (e.g. `XTenantDatabase` creds feeding
  `tenant-app`'s `secretsFrom`) — not static namespace scaffolding. Per-app
  workload identity (`serviceAccountName`, IRSA-style annotations) remains a
  separate, small, opt-in `tenant-app` field if a concrete need arises.

---

## Open ideas — `devSpace` hardening (not started)

The `devSpace` twin (`<appName>-dev`) currently shares the *same* `envFrom`
Secrets (e.g. Vault-backed app secrets, database creds) as production
whenever `devSpace.enabled: true`. These ideas reduce that exposure, roughly
in priority order:

- [ ] **`devSpace.productionOverride`** — when `environment: prod`,
  `devSpace.enabled: true` alone is *not* enough; also require
  `devSpace.productionOverride: true`. This is a self-documenting,
  auditable double-opt-in (visible in XR diffs/PRs) — not a hard
  cluster-enforced gate. Discussed and considered "quite complicated for
  this release" — deferred, but the design (KCL: `devSpaceEnabled =
  _devSpaceRequested and (environment != "prod" or _devSpaceProdOverride)`)
  is agreed and ready to implement when prioritized.

- [ ] **Scoped `ServiceAccount` + `Role`/`RoleBinding` per `devSpace`** —
  emit RBAC scoped to exactly `pods/exec`, `pods/portforward`,
  `deployments/scale` on `<appName>-dev` only. This is the credential a
  future CLI/broker tool would hand to a developer instead of a
  namespace-wide kubeconfig — the concrete piece that makes a "rent a dev
  environment" workflow safe. Natural follow-up once a CLI tool exists that
  consumes it.

- [ ] **Remote debugger port** — `devSpace.debugPort` (Node `--inspect`,
  Python `debugpy`, Go `dlv`) + a ClusterIP-only `Service` scoped to
  `<appName>-dev`, so devs `kubectl port-forward` straight to a debugger
  without Telepresence/Mirrord. Lowest-friction "next small thing" if/when
  `devSpace` work resumes.

- [ ] **VS Code "Attach to Running Container" workflow** — document
  attaching directly to `<appName>-dev` via `kubectl exec` (no tunnel tool
  needed at all, since the pod already has prod-identical deps/env). Docs
  - only addition to `local-dev-tunneling.md`.

- [ ] **Ephemeral DB branch/clone for `devSpace`** — biggest security
  upgrade but biggest lift: instead of reusing the prod `database` role,
  provision a throwaway CNPG clone via `XTenantDatabase` so dev mistakes
  can't touch prod data. Depends on CNPG branching/cloning support being
  validated for this stack.

- [ ] **Auto-scale-down / TTL for `devSpace`** — Kyverno policy or CronJob
  that scales `<appName>-dev` back to `0` after N hours of inactivity, since
  a scaled-up `devSpace` carries live prod credentials.

---

## CLI / tunneling tool (future, separate effort)

User intends to build a CLI that opens tunnel connections to `devSpace`
pods. The scoped-RBAC item above is the prerequisite this CLI would consume
— design that RBAC shape together with the CLI's auth model when that work
starts, rather than guessing the shape now.
