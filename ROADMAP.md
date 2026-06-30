# ROADMAP

Status: `[ ]` open · `[~]` in progress · `[x]` shipped · `[-]` decided not to pursue

**Table of Contents**
- [ROADMAP](#roadmap)
  - [Shipped](#shipped)
    - [v0.1.0 / v0.1.1 - Gitea XRD Baseline](#v010--v011---gitea-xrd-baseline)
    - [v0.2.0 / v0.2.1 / v0.2.5 / v0.2.6 — XTenantApp baseline + SSO Middle Integration](#v020--v021--v025--v026--xtenantapp-baseline--sso-middle-integration)
    - [v0.2.2 / v0.2.4 — XTenantDatabase dynamic tier resolution](#v022--v024--xtenantdatabase-dynamic-tier-resolution)
    - [v0.2.7 — Gitea XRD additions](#v027--gitea-xrd-additions)
  - [Active / Planned](#active--planned)
    - [DevSpace Phase 3 — own minor version bump](#devspace-phase-3--own-minor-version-bump)
    - [Guardian Framework — platform-injected quality \& security](#guardian-framework--platform-injected-quality--security)
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
- [x] `devSpace` debug-twin Deployment (`<appName>-dev`, replicas 0, no Service/Ingress, shares env/envFrom)
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
- [-] Build Matrix Permission for setting up team permissions

---

## Active / Planned

### DevSpace Phase 3 — own minor version bump

DevSpace turns the existing debug-twin Deployment into a first-class developer workspace:
exec into a live environment with real secrets, debug with real traffic, validate hotfixes
before CI. The SRE Agent and AI agent workflows depend on these primitives.

**Tier 1 — make the pod usable (must-have for release)**

- [ ] `devSpace.resources` — separate resource requests/limits for the dev pod. Debugging
  tools (language servers, profilers, IDE agents) need more memory than the production app.
  Default: no limits (dev pods cost-controlled by namespace ResourceQuota).
- [ ] `devSpace.securityContext` — opt-in overrides: `runAsUser`, `runAsGroup`,
  `readOnlyRootFilesystem` (default `false` for devSpace — writable rootfs allows
  `apt install`/`pip install` without a custom image). Single highest-impact field for
  making `kubectl exec` useful.
- [ ] `devSpace.env` — extra environment variables layered on top of main app env.
  Lets devs set `DEBUG=true`, `LOG_LEVEL=trace`, `NODE_OPTIONS=--inspect=...` without
  touching production config. devSpace wins on key collision.
- [ ] `devSpace.args` — container args override (parallel to `devSpace.command`).
  Useful for passing debug flags without replacing the entire entrypoint.

**Tier 2 — safety & access control (prerequisite for traffic interception)**

- [ ] `devSpace.productionOverride` — when `environment: prod`, `devSpace.enabled: true`
  alone is not enough; also require `devSpace.productionOverride: true`. KCL:
  `devSpaceEnabled = requested and (environment != "prod" or prodOverride)`.
  Self-documenting, visible in XR diffs and PRs.
- [ ] Scoped `ServiceAccount` + `Role`/`RoleBinding` — emit RBAC granting exactly
  `pods/exec`, `pods/portforward`, `deployments/scale` on `<appName>-dev` only.
  This is what a future CLI hands to developers instead of a namespace-wide kubeconfig.
  Also the minimum RBAC Mirrord operator mode needs to target devSpace pods.
- [ ] Auto-scale-down / TTL — Kyverno policy or CronJob that scales `<appName>-dev` to
  `0` after N hours of inactivity (configurable via `wxops.cloud/devspace-ttl: "4h"`).
  An abandoned devSpace with a live Mirrord session silently drops intercepted requests.

**Tier 3 — traffic interception & live debugging**

Headline capability: attach to real cluster traffic for hotfix debugging without touching
the production workload.

- [ ] `devSpace.tunneling.mode` — `"none"` (default), `"mirrord"`, `"telepresence"`.
  Controls annotations/labels the composition sets on the devSpace Deployment. Does NOT
  install Mirrord/Telepresence — cluster prerequisites, like cert-manager for TLS.
- [ ] `devSpace.tunneling.targetDeployment` — which Deployment to mirror/intercept from.
  Defaults to `<appName>`.
- [ ] `devSpace.tunneling.mirrord` — Mirrord-specific config:
  - `mode`: `"mirror"` (default, read-only — safe for observation) or `"steal"` (full
    intercept — requires `productionOverride` if `environment: prod`)
  - `filter`: HTTP header filter for steal mode (e.g. `x-debug-user: alice`)
  - `operatorRef`: optional mirrord-operator policy CRD name
- [ ] `devSpace.tunneling.telepresence` — Telepresence-specific config:
  - `intercept`: set up intercept annotations
  - `previewURL`: enable Telepresence preview URL generation
- [ ] `devSpace.debugPort` — expose a debugger port (`--inspect`, `debugpy`, `dlv`) via
  ClusterIP-only Service on `<appName>-dev`. Works standalone or with tunnel tools.
- [ ] `devSpace.volumes` — PVC for persistent tool installation that survives pod restarts.

**Tier 3b — documentation**

- [x] `docs/devspace.md` — comprehensive DevSpace guide (exec, file sync, mirrord,
  telepresence, A/B testing, AI agent workflow, SRE Agent, Guardian overview, safety model)
- [ ] VS Code integration docs — attaching to `<appName>-dev` via Kubernetes extension +
  Mirrord VS Code plugin for one-click traffic mirroring

**Tier 4 — advanced / future**

- [ ] Ephemeral DB branch — provision a throwaway CNPG clone via `XTenantDatabase`
  (tier: dedicated, small) so dev mistakes can't touch prod data. Pairs with steal mode:
  real traffic, writes go to ephemeral clone.
- [ ] W'xOps CLI — wraps Mirrord/Telepresence workflow: scale up devSpace, configure
  tunnel, attach debugger, tear down on exit. Separate repo; design RBAC shape (Tier 2)
  with the CLI auth model.

---

### Guardian Framework — platform-injected quality & security

Guardian injects sidecars into the devSpace pod — quality and security enforcement that
runs alongside the developer's process without requiring them to install anything.

The platform owns the devSpace pod spec. Guardian is the platform's contribution to that
pod: scanning, audit trail, AI code review, pre-installed tools — all without the
developer lifting a finger.

**Recommended rollout order:**
```
Tier 1 + Tier 2 + Guardian Phase 1 → Tier 3 + Guardian Phase 2 → Guardian Phase 3
```

**Phase 1 — scanning & tooling injection**

- [ ] `guardian-tools` init container — pre-installs approved debugging tools
  (`debugpy`, `dlv`, `node --inspect`, `pprof`, `curl`, `jq`, `psql`, `grpcurl`) into
  a shared `emptyDir` at `/opt/guardian-tools`. Rootfs stays read-only; tools come from
  the init container. Solves "writable rootfs just to install `curl`" cleanly.
- [ ] `guardian-scan` sidecar — runs Trivy/Grype + Semgrep continuously against the
  devSpace filesystem. Watches for new CVEs (dependencies), SAST findings (code changes),
  and image layer issues. Reports via pod annotations + structured logs. Advisory only —
  enforcement stays in CI/CD.
- [ ] Guardian tools catalog — platform-maintained container image per language ecosystem
  (`node`, `python`, `go`, general). Versioned, scannable, auditable.

**Phase 2 — audit & compliance**

- [ ] `guardian-audit` sidecar — captures all devSpace activity for compliance and
  incident forensics: shell commands (via `auditd` / shared PID namespace), file changes
  (inotify), network connections (conntrack/eBPF), tunnel session events.
  Structured JSON logs → SIEM. Makes steal mode on production *defensible*, not just gated.
- [ ] Guardian findings as Crossplane status — surface `status.guardian.lastScanResult`,
  `status.guardian.highFindings` on `XTenantApp`. Kyverno policies can alert when
  devSpace has been up >2h with unresolved HIGH findings.

**Phase 3 — AI guardrail (depends on LLM infrastructure)**

- [ ] `guardian-ai` sidecar — real-time code review that watches file changes in the
  devSpace pod and provides feedback before commit. Designed for hotfix-under-pressure
  scenarios where CI is bypassed:
  - Detects risky patterns: raw SQL, missing input validation, privilege escalation
  - Flags drift from established codebase patterns
  - Optional: requires guardian approval before `git push` from devSpace pod
  - LLM must be self-hosted (Ollama in-cluster, private Claude endpoint behind VPN) —
    the pod has access to production secrets and real traffic; no third-party API calls

**XR interface:**
```yaml
devSpace:
  guardian:
    enabled: true
    scanning: true   # Phase 1
    audit: true      # Phase 2
    ai: false        # Phase 3 — opt-in, requires LLM infra
    tools: true      # Phase 1
```

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
  stays focused on `Deployment`/`Service`/`Ingress`/`devSpace`. Vault-backed secrets and
  databases are provisioned separately and consumed via `envFrom.secretRef`.
