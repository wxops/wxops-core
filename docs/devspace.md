# DevSpace — In-Cluster Developer Environment

DevSpace is a platform-provisioned parallel deployment running alongside your production
application inside the same Kubernetes namespace. It shares the same infrastructure —
Vault secrets, database connections, monitoring, logging, service mesh — with zero
configuration required from the developer.

**DevSpace is not a sandbox.** It does not simulate, mock, or duplicate production
infrastructure. It is a second lane inside the real cluster, already wired to everything
your application needs, scaled to zero at rest.

---

## Why this is different

| Traditional approach | DevSpace approach |
|---|---|
| Spin up sandbox namespace + duplicate secrets + clone DB + wire monitoring | `devSpace.enabled: true` → done |
| Test a Claude integration locally with a fake API key | Run code inside the cluster pod with the real Vault-injected key |
| Wait 8–15 min CI/CD cycle to test a changed prompt template | Sync file to pod → hot-reload → test in seconds |
| SRE SSHs into prod, guesses at fix, deploys via CI | Agent reads real logs → injects fix into devSpace → validates with mirrored traffic → opens PR |

The core insight: **secrets, database connections, and monitoring already exist in
the cluster.** DevSpace inherits all of it without duplication. The cost is one
extra Deployment at `replicas: 0` most of the time.

---

## How it works

When `devSpace.enabled: true`, the platform composes a second `<appName>-dev`
Deployment in the same namespace as your production app:

- **`replicas: 0` by default** — zero cost at rest, scale up on demand
- **No `Service` or `Ingress`** — zero external exposure unless you opt in
- **Inherits `env`, `envFrom`, `secretsFrom`** — same Vault secrets, same database
  credentials, same environment configuration
- **Same network identity** — reaches all in-namespace Services and cluster-internal
  endpoints exactly as the production pod does
- **Observable** — same logging stack, same Prometheus metrics, same tracing

```yaml
spec:
  parameters:
    appName: payment-api
    namespace: team-alpha
    image: ghcr.io/team-alpha/payment-api:1.4.2
    secretsFrom:
      app:
        enabled: true       # Vault-backed secret already mounted in prod
      database:
        enabled: true       # DB creds already mounted in prod

    devSpace:
      enabled: true         # parallel pod, same secrets, zero external exposure
      replicas: 0           # scale up on demand
      command: ["uvicorn", "main:app", "--reload", "--host", "0.0.0.0"]
```

---

## Quickstart

```bash
# 1. Scale up the devSpace pod (platform RBAC lets you do this with your OIDC identity)
kubectl -n team-alpha scale deployment/payment-api-dev --replicas=1

# 2. Watch it start with the same env as prod
kubectl -n team-alpha logs -f deployment/payment-api-dev

# 3. Exec in — real secrets, real DB, real network. No config.
kubectl -n team-alpha exec -it deployment/payment-api-dev -- bash

# 4. Scale back down when done
kubectl -n team-alpha scale deployment/payment-api-dev --replicas=0
```

---

## Developer workflows

### 1 — Exec and debug

The simplest use case. Scale the pod up, exec in, and interact with the running
application in a real environment.

```bash
kubectl -n <namespace> exec -it deployment/<appName>-dev -- bash

# Inside the pod: real secrets are in the environment
echo $ANTHROPIC_API_KEY       # Vault-injected, present already
psql $DATABASE_URL            # real DB connection, no config

# Run a one-off test against real infrastructure
python scripts/test_rag_pipeline.py
```

Useful for: quick inspection, running migration checks, verifying environment
configuration, ad-hoc testing.

### 2 — File sync and hot reload (AI-era development)

For iterative development — especially AI integrations where the feedback loop must
be seconds, not minutes.

**How it works:**

```
Edit code locally → sync to pod → hot-reload triggers → test with real data
```

**Platform side** (compose in `devSpace`):
```yaml
devSpace:
  enabled: true
  command: ["uvicorn", "main:app", "--reload"]  # or nodemon, air, watchmedo
  fileSync:
    enabled: true      # emptyDir volume at mountPath, writable regardless of
    mountPath: /app    # main app's readOnlyRootFilesystem setting
```

**Developer side** — use [mutagen](https://mutagen.io/) for continuous sync:

```bash
# One-time session setup
mutagen sync create --name payment-api-dev \
  ./src \
  k8s://team-alpha/payment-api-dev-<hash>:/app

# Files sync on every save. Pod hot-reloads automatically.
# ANTHROPIC_API_KEY is already in the pod — no export, no .env file.

# When done
mutagen sync terminate payment-api-dev
```

Or [VS Code Remote - Kubernetes](https://marketplace.visualstudio.com/items?itemName=ms-kubernetes-tools.vscode-kubernetes-tools)
to open the pod directly as a workspace in your IDE.

**Why this matters for AI development specifically:**

When iterating on prompt templates, RAG pipeline configuration, Claude tool
definitions, or agent decision trees, you need real data and real API keys.
A local mock is insufficient; a full CI/CD cycle is too slow.

```
Change prompt template locally
  → mutagen syncs in ~1 second
  → uvicorn --reload picks it up
  → pod sends real API request with real ANTHROPIC_API_KEY
  → real response in the logs
  → iterate again
```

The entire loop takes 3–5 seconds. The same change via CI/CD takes 8–15 minutes.

### 3 — Traffic mirroring (mirrord)

Mirror real production traffic into the devSpace pod. Your code handles actual
requests — without affecting the production pod or real users.

```bash
# Mirror traffic from the main Deployment to the devSpace pod
# Your local process runs with the pod's environment (secrets included)
mirrord exec \
  --target deployment/payment-api-dev \
  --target-namespace team-alpha \
  -- uvicorn main:app --reload
```

mirrord copies incoming requests to both the production pod and your process.
The production pod still handles real users. You observe real request patterns,
real payloads, real edge cases — without any user seeing your changes.

**Modes:**

| Mode | Command | Effect |
|---|---|---|
| Mirror (default) | `mirrord exec --target ...` | Traffic copied to your process; prod unaffected |
| Steal | `mirrord exec --steal --target ...` | Traffic redirected to your process; use with care |

Mirror mode is safe in all environments. Steal mode on production requires
`devSpace.productionOverride: true` in the XR (double-opt-in, auditable).

### 4 — Traffic interception (Telepresence)

Full tunnel: your local process gets the pod's network identity and handles all
traffic routed to the devSpace pod.

```bash
telepresence connect --namespace <namespace>

telepresence intercept <appName>-dev \
  --port <containerPort>:<containerPort> \
  --namespace <namespace>

# Optional: extract env vars to a local .env file instead of full intercept
telepresence intercept <appName>-dev \
  --port <containerPort>:<containerPort> \
  --namespace <namespace> \
  --env-file .env.local
```

Telepresence is heavier (requires a cluster-side Traffic Manager) but gives you
full network identity — useful when you need to test service-to-service calls
that originate from the pod's identity, not your laptop's.

---

## A/B testing and feature flags

When `devSpace.trafficWeight` is set, the platform composes a `Service` for the
devSpace pod and a Traefik `TraefikService` weighted split between the production
Deployment and the devSpace Deployment.

```yaml
devSpace:
  enabled: true
  trafficWeight: 10    # route 10% of real traffic to devSpace pod
```

This creates a three-mode spectrum via a single parameter:

| `trafficWeight` | Mode | Use case |
|---|---|---|
| `0` (default) | Off — devSpace has no Service | Debug only, no external traffic |
| `1–99` | A/B split — real users reach devSpace | Feature validation, performance comparison |
| `100` | Full canary — all traffic to devSpace | Pre-promotion validation |

**Feature flags fall out naturally:** the devSpace Deployment inherits `env` and
`envFrom` from the main app, but you can layer `devSpace.env` on top to enable
flags that differ from production:

```yaml
devSpace:
  trafficWeight: 20
  env:
    - name: FEATURE_NEW_RANKING
      value: "true"
    - name: LOG_LEVEL
      value: debug
```

20% of real users hit the devSpace pod with the new ranking enabled. Metrics
come from the same Prometheus stack. No feature flag service required.

> **Caution:** devSpace with `trafficWeight > 0` carries the same responsibility
> as a canary deployment. If the devSpace pod crashes, that percentage of traffic
> drops. This is a developer-controlled tool for validation — not a replacement
> for a production traffic-splitting strategy (use ArgoCD Rollouts for that).

---

## AI Agent workflow

The devSpace pod provides a pre-wired execution target for AI coding agents — real
secrets, real database, real network — without any environment setup.

**Pattern:**

```
AI Agent generates code change
  → syncs to devSpace pod (via kubectl cp or mutagen)
  → devSpace hot-reloads
  → agent reads pod logs / calls health endpoint
  → validates correctness against real infrastructure
  → opens PR if good, iterates if not
```

**What makes this work:**
- The agent needs no Vault configuration, no DB credentials, no API keys — they
  are already in the pod
- The agent uses the scoped `ServiceAccount` (from `devSpace.rbac`) to exec and
  scale — no cluster-admin access required
- Mirrord provides real traffic for the agent to test against
- The platform's logging stack captures all activity automatically

**Example: testing a new Claude integration without deploying to prod:**

```python
# Agent writes the integration, syncs it to devSpace
subprocess.run(["kubectl", "cp", "claude_integration.py",
                f"team-alpha/{devspace_pod}:/app/claude_integration.py"])

# Trigger a test inside the pod
result = subprocess.run([
    "kubectl", "exec", devspace_pod, "-n", "team-alpha",
    "--", "python", "-c",
    "from claude_integration import run; print(run('test query'))"
], capture_output=True)

# ANTHROPIC_API_KEY was already in the pod — real API call, real response
# Agent reads result and decides: iterate or promote to PR
```

---

## SRE Agent — intelligence injector

The SRE Agent is the most advanced use of DevSpace: an AI system that autonomously
debugs production incidents by injecting targeted fixes into the devSpace pod and
validating them against mirrored production traffic — without any human intervention
in the diagnosis and validation loop.

**Incident response flow:**

```
Alert fires (latency spike / error rate / availability)
    ↓
SRE Agent reads logs + metrics (already instrumented — no setup)
    ↓
Forms hypothesis: "DB connection pool exhausted under load"
    ↓
Generates targeted fix (increase pool size, add retry backoff)
    ↓
Injects fix into devSpace pod (exec + file sync)
    ↓
Enables traffic mirror (mirrord) — real production traffic hits devSpace
    ↓
Validates: error rate drops in devSpace metrics, latency normalizes
    ↓
Opens PR with fix + validation evidence
    ↓
Human SRE reviews PR — fix already validated against real traffic
```

**What the platform provides for the SRE Agent:**

Via `devSpace.agentAccess.enabled`, the platform composes a `Role` +
`RoleBinding` granting a designated ServiceAccount (the agent's identity) exactly:
- `deployments/scale` on `<appName>-dev`
- `pods/exec`, `pods/portforward`, `pods/log` scoped to devSpace pods
- Read access to the namespace's `Events`

The agent has a real, auditable Kubernetes identity — not cluster-admin access.
All activity is logged by the platform's audit stack.

**Why "no manual reproduction steps" matters:**

Traditional incident response: alert → on-call engineer woken up → SSH access
requested → reproduce locally (or not) → guess at fix → deploy to staging → validate
→ deploy to prod. 45–90 minutes minimum.

SRE Agent with DevSpace: alert → agent activates → fix injected → validated →
PR ready. Human reviews a validated fix, not a hypothesis. Incident resolution
time measured in minutes, not hours.

> **Status:** SRE Agent architecture is defined. The platform RBAC primitives
> (Tier 2 DevSpace roadmap) are the prerequisite. The agent intelligence layer
> is a separate workload that consumes those primitives — see [ROADMAP.md](../ROADMAP.md).

---

## Guardian Framework (platform-injected safety)

When DevSpace is used for incident response or production traffic interception, the
platform can inject safety sidecars alongside the developer's container — without
requiring any developer action.

```
Pod: <appName>-dev
├── container: app           (developer's process — untouched)
├── sidecar: guardian-scan   (continuous SAST + CVE scanning of code changes)
├── sidecar: guardian-audit  (session logging — every exec, every file change)
├── sidecar: guardian-ai     (AI code review for hotfixes under pressure)
└── init: guardian-tools     (pre-installed debugger/profiler tooling)
```

Guardian is additive — it runs silently alongside the developer's process and
never blocks the debug workflow. Findings are advisory in the debug environment;
enforcement lives in CI/CD (the commit gate).

> **Status:** Guardian is planned after DevSpace Tier 3 ships. See
> [ROADMAP.md](../ROADMAP.md) for the phased rollout.

---

## Access control

DevSpace access is provisioned by the platform alongside the devSpace Deployment.
Developers use their OIDC identity (via the cluster's Impersonate Proxy) — no
separate credentials required.

```yaml
devSpace:
  rbac:
    enabled: true
    subjects:
      - kind: Group
        name: team-alpha-developers    # OIDC group
        apiGroup: rbac.authorization.k8s.io
```

The platform emits a `Role` + `RoleBinding` granting exactly:
- Scale `<appName>-dev` Deployment
- `pods/exec`, `pods/portforward`, `pods/log` on devSpace pods
- Create/delete pods in the namespace (for mirrord agent)

No namespace-wide kubeconfig. No cluster-admin. The scoped `ServiceAccount`
is what a future W'xOps CLI will use to provide one-command environment access.

---

## Safety model

| Scenario | Risk | Guardrail |
|---|---|---|
| Mirror mode, `staging` | Low — read-only, prod unaffected | None required |
| Steal mode, `staging` | Medium — dev handles real requests | Use HTTP header filter (`x-debug-user`) |
| Mirror mode, `prod` | Medium — real user data visible | `devSpace.productionOverride: true` required |
| Steal mode, `prod` | High — dev code handles real prod traffic | `productionOverride: true` + `tunneling.mirrord.mode: steal` (double opt-in) + Guardian audit |
| Abandoned session | Medium — intercepted requests dropped | Auto-scale-down TTL annotation `wxops.cloud/devspace-ttl: "4h"` |

The platform enforces the production override at the KCL composition level —
a devSpace pod cannot be enabled in `environment: prod` without the explicit
`productionOverride: true` flag visible in the XR diff and PR.

---

## Choosing between mirrord and Telepresence

| | mirrord | Telepresence |
|---|---|---|
| Default mode | Mirror (read-only copy) | Intercept (redirects traffic) |
| Cluster footprint | None — agent injected per-session | Traffic Manager Deployment required |
| Scope | Single pod — natural fit for devSpace | Namespace or service-wide |
| Best for | Fast attach, real-traffic observation, AI agent workflows | Full network identity replacement, preview URLs |
| W'xOps recommendation | Primary path | Fallback for existing users |

Neither tool is installed by the composition — same model as cert-manager for TLS.
Install once per cluster, use from any devSpace pod.

---

## Prerequisites

- `devSpace.enabled: true` in the `XTenantApp` XR
- OIDC identity configured (Impersonate Proxy + Vault Kubernetes Auth)
- **For mirrord:** `mirrord` CLI installed locally. Optional:
  [mirrord-operator](https://metalbear.com/mirrord/docs/overview/teams/) for
  policy enforcement and audit logging.
- **For telepresence:** Traffic Manager installed in-cluster
  (`telepresence helm install`), `telepresence` CLI installed locally.
- **For file sync:** `mutagen` CLI installed locally, or VS Code Remote -
  Kubernetes extension.
- **For A/B / traffic weight:** Traefik with `TraefikService` CRD available
  (default in W'xOps clusters).
