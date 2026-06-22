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

## `XTenantDatabase` — dynamic tier resolution — shipped v0.2.2, fixed v0.2.4

- [x] Replace hardcoded `_clusterTierMap` with dynamic discovery via
      `function-extra-resources`.
- [x] `XPlatformDatabaseCluster.shared` toggle + `status` subresource
      (clusterName, namespace, shared, environment) for pool discovery.
- [x] `tier: shared` — pool-based auto-assignment: least-loaded cluster,
      environment isolation, `dbName` collision check, sticky assignment
      via status writeback.
- [x] `tier: dedicated` — compose a child `XPlatformDatabaseCluster` XR
      inline (1 cluster = 1 database, fully isolated), sized via
      `dedicatedCluster` parameters.
- [x] Vault path restructure: `{owner}/{dbName}/connection-creds` →
      `{owner}/databases/{dbName}/connection-creds` (logical:
      `tenants/{owner}/databases/{dbName}/...`).
- [x] `function-extra-resources` provider + `crossplane.yaml` dependency.

### v0.2.4 bug fixes — discovery label contract

v0.2.2 assumed the composition could set discovery labels on XRs via dxr
updates. In practice, **Crossplane writes `status` from dxr but ignores
`metadata.labels`**. v0.2.4 fixes this with a label contract:

- [x] Extra resources read from pipeline context
      (`ctx["apiextensions.crossplane.io/extra-resources"]`), not
      `option("params").extraResources`.
- [x] Resources in context are unwrapped (`{apiVersion, kind, ...}`),
      not `{resource: ...}`.
- [x] `_get` helper guards `d or {}` against KCL `Undefined` dicts.
- [x] `matchLabels` required on every selector (v0.3.0 silently skips
      empty `matchLabels`).
- [x] Pool filtering by `status.shared` + `status.environment` in KCL
      (with fallback to `spec.parameters` for unreconciled clusters).
- [x] Discovery labels must be in the XR manifest (user/GitOps):

| Resource | Required label |
|---|---|
| `XPlatformDatabaseCluster` | `wxops.cloud/managed-by: platform-database-clusters` |
| `XTenantDatabase` | `wxops.cloud/tenant-database: "true"` |

---

## Open ideas — Vault Database Secrets Engine (not started)

Vault's Database Secrets Engine for **dynamic credential management** —
Vault connects to CNPG clusters with restricted privileges (user/role
management only, no schema/extension/data access) and issues short-lived,
auto-rotated credentials for tenants.

- [ ] **Design mount/path topology** — single mount per cluster vs.
      per-tenant mounts. Key question: does the ESO pipeline pull once and
      fan out, or do tenants read directly from Vault? Each
      `ExternalSecret` read from a dynamic secrets path generates a new
      lease, so the pipeline needs to handle rotation gracefully.
- [ ] **`SecretBackendConnection`** on `XPlatformDatabaseCluster` —
      per-cluster Vault connection with a restricted PostgreSQL role
      (`CREATEROLE` only). Opt-in toggle (`vaultDatabaseBackend.enabled`).
- [ ] **`SecretBackendRole`** on `XTenantDatabase` — per-database
      dynamic credential template (creation/revocation SQL scoped to the
      tenant's database).
- [ ] **ESO lease lifecycle** — `refreshInterval` triggers new leases,
      old ones get revoked. Different from the current static flow where
      CNPG creds don't change unless manually rotated.
- [ ] **Vault KV2 mount composition** — optionally compose a
      `vault.vault.upbound.io/v1alpha1 Mount` on `XPlatformDatabaseCluster`
      so the platform admin doesn't need to pre-create Vault mounts
      out-of-band. Requires `provider-vault` install.

Prerequisite: the current static credential flow (CNPG creates creds →
ESO PushSecret → Vault KV2) remains the default. Dynamic secrets layer
on top as an opt-in path — both can coexist (static for admin/superuser,
dynamic for tenant app credentials).

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
- [-] **`tenant-app` `databaseRef` for end-to-end credential wiring** —
  considered adding a field that composes an ExternalSecret to pull from
  Vault into the app namespace automatically. Decision: keep the boundary
  clean — the ExternalSecret is a GitOps/platform concern, provisioned
  separately. `tenant-app` stays focused on the workload, `tenant-database`
  on provisioning + Vault push. The bridging ExternalSecret is intentionally
  the platform/GitOps layer's responsibility.
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

## DevSpace overhaul — phase 3 (planned, own release)

DevSpace is a productivity differentiator — a debug twin that gives devs
a prod-identical environment they can exec into, install tools, attach
debuggers, and tunnel traffic through, without touching the real workload.
Today it's a bare-bones Deployment with `sleep infinity`. Phase 3 makes it
a first-class developer workspace.

The core value proposition: **hotfix debugging in a live environment
without touching production traffic.** A developer scales up `<appName>-dev`,
points Mirrord or Telepresence at it to mirror/intercept traffic from the
real deployment, debugs the issue with real data flows, validates the fix,
then commits — all without a risky deploy-to-staging-and-pray cycle. This
is where W'xOps turns "6-hour incident → 30-minute hotfix" for its users.

Target: own minor version bump (`tenant-app` package) to emphasize
DevSpace as a headline feature.

### Tier 1 — make the pod usable (must-have for the release)

These are the baseline fields that make DevSpace actually work for
debugging. Without them, devs hit permission errors trying to install
anything and run out of memory running IDE agents.

- [ ] **`devSpace.resources`** — separate resource requests/limits for
  the dev pod. Debugging tools (language servers, IDE agents, profilers)
  need more memory than the app itself, and production limits choke them.
  Default: no limits (inherit nothing — dev pods are cost-controlled by
  namespace ResourceQuota, not per-pod limits).

- [ ] **`devSpace.securityContext`** — opt-in overrides for the dev
  container. The main app typically runs non-root with a read-only
  rootfs — correct for production, unusable for debugging. Key fields:
  `runAsUser` (default: inherit main), `runAsGroup`,
  `readOnlyRootFilesystem` (default: `false` for devSpace — writable fs
  lets devs `apt install`/`pip install` without a custom image),
  `allowPrivilegeEscalation`. This is the single most impactful field —
  it's what makes `kubectl exec` into a devSpace pod actually useful.

- [ ] **`devSpace.env`** — extra environment variables layered on top of
  the main app's `env` + `envFrom`. Lets devs set `DEBUG=true`,
  `LOG_LEVEL=trace`, `NODE_OPTIONS=--inspect=0.0.0.0:9229` without
  touching production config. Appended after the main env block — if a
  key collides, devSpace wins (Kubernetes last-writer-wins on env).

- [ ] **`devSpace.args`** — container args override, parallel to the
  existing `devSpace.command`. Useful for passing debug flags without
  replacing the entire entrypoint.

### Tier 2 — safety & access control (hard prerequisite for traffic interception)

These prevent DevSpace from being a security liability. **Tier 2 must
land before or alongside Tier 3** — traffic interception (Mirrord/
Telepresence) without these safety gates is the "writable root +
live prod creds + real traffic + no audit trail" scenario to avoid.

- [ ] **`devSpace.productionOverride`** — when `environment: prod`,
  `devSpace.enabled: true` alone is NOT enough; also require
  `devSpace.productionOverride: true`. Self-documenting, auditable
  double-opt-in visible in XR diffs/PRs — not a cluster-enforced gate.
  KCL: `devSpaceEnabled = _devSpaceRequested and (environment != "prod"
  or _devSpaceProdOverride)`. Design agreed, ready to implement.

- [ ] **Scoped `ServiceAccount` + `Role`/`RoleBinding`** — emit RBAC
  scoped to exactly `pods/exec`, `pods/portforward`,
  `deployments/scale` on `<appName>-dev` only. This is the credential a
  future CLI/broker tool hands to a developer instead of a namespace-wide
  kubeconfig. The concrete piece that makes "rent a dev environment" safe.
  Also the minimum RBAC Mirrord's operator mode needs to target the
  devSpace pod specifically.

- [ ] **Auto-scale-down / TTL** — Kyverno policy or CronJob that scales
  `<appName>-dev` back to `0` after N hours of inactivity (configurable
  via annotation, e.g. `wxops.cloud/devspace-ttl: "4h"`). A scaled-up
  devSpace carries live prod credentials — it shouldn't stay up
  indefinitely. Critical once traffic interception is in play: an
  abandoned devSpace with an active Mirrord session silently drops
  intercepted requests.

### Tier 3 — traffic interception & live debugging (core of phase 3)

This is the headline capability — what makes DevSpace a productivity
multiplier for hotfixes and incident response. Both tools let a dev
attach their local process (or the devSpace pod's process) to real
cluster traffic for live debugging.

**Tool comparison for W'xOps:**

| | Mirrord | Telepresence |
|---|---|---|
| Architecture | Sidecar/agent per pod, process-level interception | Cluster-wide traffic manager, network-level interception |
| Cluster footprint | None (agent injected at connect time) | Traffic manager Deployment in `ambassador` namespace |
| Scope | Single pod — natural fit for devSpace twin | Namespace or service-wide — broader blast radius |
| Traffic modes | Mirror (read-only copy) or Steal (full intercept) | Intercept (with header-based routing for shared) |
| W'xOps fit | Better — scoped to `<appName>-dev`, no shared daemon | Heavier but more mature ecosystem (IDE plugins, preview URLs) |
| Operator mode | [mirrord-operator](https://metalbear.com/mirrord/docs/overview/teams/) — cluster-level policy, audit, concurrent sessions | Built-in to traffic manager |

**Recommendation**: support both, prefer Mirrord as the default path.
Mirrord's process-level interception scoped to a single devSpace pod
aligns with W'xOps' per-app isolation model. Telepresence is the
fallback for teams already using it or needing preview URLs.

Implementation:

- [ ] **`devSpace.tunneling.mode`** — `"none"` (default), `"mirrord"`,
  `"telepresence"`. Controls annotations/labels the composition sets on
  the devSpace Deployment to make the pod discoverable and configurable
  by each tool. `"none"` is the current behavior — `sleep infinity`,
  manual exec. This field does NOT install Mirrord/Telepresence — those
  are cluster prerequisites, like cert-manager for TLS.

- [ ] **`devSpace.tunneling.targetDeployment`** — which Deployment to
  mirror/intercept traffic from. Defaults to `<appName>` (the main
  Deployment composed by tenant-app). Lets devs point at a different
  workload if needed (e.g. a gateway that routes to this app).

- [ ] **`devSpace.tunneling.mirrord`** — Mirrord-specific configuration:
  - `mode`: `"mirror"` (default, read-only traffic copy — safe for
    observation) or `"steal"` (full intercept — needed for response
    debugging, dangerous). Mirror mode is the safe default: the dev
    sees real requests but the real pod still handles them. Steal mode
    requires `productionOverride` if `environment: prod`.
  - `filter`: HTTP header filter for steal mode (e.g.
    `x-debug-user: alice`) — only intercept requests matching the
    filter, let the rest flow to the real pod. Prevents a single
    dev's debug session from disrupting all users.
  - `operatorRef`: optional reference to a mirrord-operator policy
    (CRD name) — the operator enforces which namespaces/pods can be
    targeted and logs all sessions for audit.

- [ ] **`devSpace.tunneling.telepresence`** — Telepresence-specific
  configuration:
  - `intercept`: `true`/`false` — whether to set up intercept
    annotations. When true, the devSpace pod gets the labels/annotations
    Telepresence needs to register an intercept handler.
  - `previewURL`: `true`/`false` — enable Telepresence preview URL
    generation (requires Ambassador Cloud or self-hosted).

- [ ] **Annotations emitted by the composition** (per mode):
  - Mirrord: `wxops.cloud/devspace-tunnel: mirrord`,
    `wxops.cloud/devspace-target: <appName>`,
    `wxops.cloud/devspace-mirrord-mode: mirror|steal` — consumed by
    the CLI/docs to generate the correct `mirrord.json` config.
  - Telepresence: `wxops.cloud/devspace-tunnel: telepresence`,
    `telepresence.getambassador.io/inject-traffic-agent: enabled` —
    the standard annotation Telepresence looks for.

- [ ] **`devSpace.debugPort`** — expose a debugger port (Node
  `--inspect`, Python `debugpy`, Go `dlv`) via a ClusterIP-only Service
  scoped to `<appName>-dev`. Devs `kubectl port-forward` straight to a
  debugger without any tunnel tool. Pairs with `devSpace.env` for
  setting `NODE_OPTIONS`/`DEBUGPY_PORT`/etc. Works standalone or
  combined with Mirrord/Telepresence (tunnel real traffic + attach
  debugger = full live-debugging workflow).

- [ ] **`devSpace.volumes`** — mount a PVC for persistent tool
  installation that survives pod restarts. Without this, every `apt
  install` is lost when the pod cycles. Small PVC (1–5Gi), tied to the
  devSpace lifecycle.

**Danger model & guardrails:**

Traffic interception is the most powerful and most dangerous DevSpace
capability. The risk matrix:

| Scenario | Risk | Guardrail |
|---|---|---|
| Mirror mode on staging | Low — read-only, real pod still serves | None needed beyond Tier 1 |
| Steal mode on staging | Medium — dev handles real requests, bad responses visible to testers | Header filter (only intercept `x-debug-user` requests) |
| Mirror mode on prod | Medium — dev sees real user data (PII exposure) | `productionOverride` required |
| Steal mode on prod | **High** — dev code handles real user traffic, can mutate DB/queues | `productionOverride` + steal requires explicit opt-in + audit via mirrord-operator |
| Abandoned session | Medium — intercepted requests silently dropped | TTL auto-scale-down (Tier 2) + operator session timeout |

The composition enforces: steal mode on `environment: prod` requires
both `productionOverride: true` AND `tunneling.mirrord.mode: "steal"`
(double intent). Mirror mode on prod only requires `productionOverride`.
Non-prod environments have no restrictions — devs can mirror or steal
freely on dev/staging.

**Prerequisites (not composed by tenant-app):**
- Mirrord: `mirrord` CLI installed locally by the dev. Optionally,
  [mirrord-operator](https://metalbear.com/mirrord/docs/overview/teams/)
  installed in-cluster for policy enforcement and audit logging.
- Telepresence: traffic manager installed in-cluster (`telepresence
  helm install`), `telepresence` CLI installed locally.
- Neither tool is installed by the composition — same pattern as
  cert-manager for TLS or oauth2-proxy for SSO.

### Tier 3b — documentation & developer guides

- [ ] **`docs/devspace.md`** — comprehensive DevSpace guide: what it is,
  when to use it (hotfix workflow, feature validation, incident response),
  the danger model, step-by-step for each tunneling mode.

- [ ] **`docs/local-dev-tunneling.md` update** — rewrite with concrete
  workflows: (1) plain exec (no tunnel), (2) Mirrord mirror mode,
  (3) Mirrord steal mode with header filter, (4) Telepresence intercept.
  Each with copy-paste commands and `mirrord.json`/Telepresence config.

- [ ] **VS Code integration docs** — attaching to `<appName>-dev` via
  the Kubernetes VS Code extension + Mirrord's VS Code plugin for
  one-click traffic mirroring.

### Tier 4 — advanced / future

These are high-value but high-lift, dependent on external capabilities
maturing.

- [ ] **Ephemeral DB branch/clone** — instead of reusing the prod
  `database` role, provision a throwaway CNPG clone via `XTenantDatabase`
  (tier: dedicated, small instance) so dev mistakes can't touch prod data.
  Depends on CNPG branching/cloning support being validated for this
  stack and the dynamic tier resolution shipped in v0.2.2. Pairs
  naturally with steal mode: intercept real traffic but writes go to an
  ephemeral DB clone, never touching prod data.

- [ ] **CLI / tunneling tool** — W'xOps CLI that wraps the
  Mirrord/Telepresence workflow: scale up devSpace, configure tunnel,
  attach debugger, tear down on exit. Consumes the scoped ServiceAccount
  from Tier 2. Separate repo/effort — design the RBAC shape (Tier 2)
  together with the CLI's auth model when that work starts.

---

## Guardian Framework — platform-injected quality & security (future)

The DevSpace pod is infrastructure composed by the platform, not by the
developer. This means the platform can inject sidecars, init containers,
and tooling into the debug environment — quality and security enforcement
that runs alongside the developer's process without requiring them to
install, configure, or even know about it.

**Design principle**: the developer owns their IDE, their local tools,
their workflow. The platform owns the infrastructure the code runs on —
and that includes what runs inside the DevSpace pod. Same boundary as
the golden-path health-check contract (`/healthz`, `/readyz`): the
developer picks their framework, the platform guarantees the guardrails
exist regardless.

This is not about forcing tools on developers. It's about providing
tools developers don't have time to set up themselves — especially
during incident response when a hotfix is written under pressure and
the usual CI pipeline is bypassed or shortcut.

### Why this doesn't exist yet

The market has the pieces in isolation:

- **Dev environments** (Gitpod, Codespaces, Okteto) — developer-owned,
  no platform injection point. The developer controls the pod spec.
- **Security scanning** (Snyk, Sonar, Trivy, Semgrep) — CI/CD pipeline
  tools. They run on PR push, not during active debugging. By then the
  developer has context-switched away from the problem.
- **Traffic interception** (Mirrord, Telepresence) — developer-facing,
  no platform injection, no guardrails beyond basic RBAC.

Nobody combines "debug twin next to production" + "platform-injected
scanning" + "AI guardrails" because nobody has a DevSpace-like construct
where the platform owns the pod spec but the developer uses it for
debugging. W'xOps DevSpace is that construct.

### Architecture

The Guardian runs as **platform-injected sidecars and init containers**
on the DevSpace Deployment. The developer's container (`<appName>-dev`)
is untouched — Guardian containers run alongside it in the same pod,
sharing the filesystem (via `emptyDir` or the devSpace PVC) and network
namespace.

```
Pod: <appName>-dev
├── container: app          (developer's debug process)
├── sidecar: guardian-scan   (vulnerability + SAST scanning)
├── sidecar: guardian-audit  (session logging + compliance)
├── sidecar: guardian-ai     (AI-powered code review guardrail)
└── init: guardian-tools     (pre-installs approved debug tooling)
```

The composition controls injection via a `devSpace.guardian` toggle:

```yaml
devSpace:
  enabled: true
  guardian:
    enabled: true    # inject guardian sidecars
    # Individual toggles for phased rollout:
    scanning: true   # vulnerability + SAST sidecar
    audit: true      # session logging sidecar
    ai: false        # AI guardrail (opt-in, depends on LLM infra)
    tools: true      # init container with approved tooling
```

When `guardian.enabled: false` (or DevSpace phase 3 before Guardian
ships), the pod is bare — just the developer's container. Guardian is
additive, never breaking.

### Phase 1 — scanning & tooling injection

- [ ] **`guardian-tools` init container** — pre-installs approved
  debugging tools (language debuggers, profilers, CLI utilities) into a
  shared `emptyDir` volume mounted at `/opt/guardian-tools`. The dev's
  PATH includes this directory. Tools are curated by the platform team
  and versioned in a container image — devs don't need to `apt install`
  anything. Solves the "writable rootfs just to install `curl`" problem
  cleanly: rootfs stays read-only, tools come from the init container.

- [ ] **`guardian-scan` sidecar** — runs Trivy/Grype + Semgrep
  continuously against the devSpace filesystem. Watches for:
  - New dependencies installed by the developer (scans for CVEs)
  - Code changes (runs SAST rules — SQL injection, hardcoded secrets,
    unsafe deserialization, OWASP top 10)
  - Container image layers (if the dev switches `devSpace.image`)
  Reports findings via:
  - Pod annotations (`wxops.cloud/guardian-findings: "2 HIGH, 1 MEDIUM"`)
  - Structured log output (consumed by the platform's logging stack)
  - Optional webhook to Slack/Teams/PagerDuty for high-severity findings
  Does NOT block the developer — findings are advisory. Blocking
  enforcement belongs in CI/CD (the commit gate), not the debug
  environment.

- [ ] **`guardian-tools` catalog** — platform-maintained container image
  with approved tooling per language ecosystem. Versioned, scannable,
  auditable. Examples:
  - Node.js: `node --inspect` support, `ndb`, `clinic.js`
  - Python: `debugpy`, `py-spy`, `ipdb`
  - Go: `dlv`, `pprof`
  - General: `curl`, `jq`, `psql`, `redis-cli`, `grpcurl`

### Phase 2 — audit & compliance

- [ ] **`guardian-audit` sidecar** — captures all activity in the
  devSpace pod for compliance and incident forensics:
  - Shell commands executed via `kubectl exec` (via `script(1)` or
    `auditd` in the sidecar, reading from shared PID namespace)
  - Files modified (inotify watcher on shared volumes)
  - Network connections made (conntrack or eBPF if available)
  - Mirrord/Telepresence session start/stop events
  Output: structured JSON logs shipped to the platform's SIEM/logging
  stack. Retention policy configurable per environment (prod sessions
  retained longer for compliance).

  This is what makes `steal` mode on production *defensible* — not just
  "we gated it behind `productionOverride`" but "we have a full audit
  trail of every command the developer ran and every request they
  handled."

- [ ] **Guardian findings as Crossplane status** — surface
  `guardian-scan` findings in the `XTenantApp` status subresource
  (`status.guardian.lastScanResult`, `status.guardian.highFindings`).
  Platform dashboards and Kyverno policies can key off this — e.g.
  alert if a devSpace has been up for >2h with unresolved HIGH findings.

### Phase 3 — AI guardrail (future, depends on LLM infrastructure)

- [ ] **`guardian-ai` sidecar** — AI-powered code review that watches
  file changes in real-time and provides feedback before the developer
  commits. Not a replacement for PR review — a "pair programmer for
  hotfixes" that catches the mistakes developers make under incident
  pressure:
  - Detects risky patterns: raw SQL construction, missing input
    validation, privilege escalation, unscoped database queries
  - Suggests safer alternatives inline (via a lightweight API the
    dev's IDE plugin can query)
  - Flags drift from the codebase's established patterns (e.g. "this
    repo uses parameterized queries everywhere, this file doesn't")
  - Optionally gates the commit: if the guardian-ai flags HIGH-severity
    issues, the scoped ServiceAccount (Tier 2) can be configured to
    require guardian approval before `git push` from the devSpace pod

  **LLM infrastructure dependency**: requires a self-hosted or
  API-accessible LLM with code understanding. Not sent to third-party
  APIs from the devSpace pod (the pod has access to production secrets
  and real traffic data). Options: Ollama in-cluster, a private
  Claude/GPT endpoint behind VPN, or a fine-tuned code model on
  dedicated GPU nodes.

  **Privacy constraint**: the guardian-ai sidecar sees the same
  environment as the developer (including secrets, traffic data). The
  LLM must be self-hosted or contractually guaranteed not to train on
  inputs. This is a deployment decision, not a composition concern —
  the composition just injects the sidecar, the platform team
  configures where the LLM lives.

### Interaction with DevSpace tiers

Guardian sits between Tier 2 (safety) and Tier 3 (traffic interception)
in the dependency chain:

```
Tier 1 (usable pod) → Tier 2 (safety gates) → Guardian → Tier 3 (traffic)
```

Guardian is not a hard prerequisite for Tier 3 — traffic interception
can ship without it. But Guardian makes traffic interception on
production *defensible rather than just gated*. The recommended rollout:

1. Ship Tier 1 + Tier 2 + Guardian Phase 1 (scanning/tools) together
2. Ship Tier 3 (Mirrord/Telepresence) with Guardian audit (Phase 2)
3. Guardian AI (Phase 3) is independent — ship when LLM infra is ready

### What Guardian is NOT

- Not a CI replacement — CI gates (PR checks, merge policies) remain
  the primary enforcement point. Guardian is the "shift further left"
  layer for scenarios where CI is bypassed (hotfixes, incidents).
- Not a developer-facing product — devs shouldn't need to interact
  with Guardian. It runs silently, surfaces findings passively, and
  only blocks in extreme cases (opt-in, HIGH-severity, AI gate).
- Not an IDE plugin — the developer uses their own IDE. Guardian runs
  server-side in the pod. IDE integration (if any) is a thin API
  client, not a required component.
