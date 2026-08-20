# Observability — ServiceMonitor & PodMonitor

> **Status: implemented** in `package/tenant-app/` as `spec.parameters.monitoring`.
> The one deviation from the design below: the app Service port is still unnamed,
> so the emitted endpoint targets `targetPort` rather than a port name. That was
> the zero-risk option — see [What changes](#what-changes).
>
> **Scope:** how `XTenantApp` exposes application metrics to Prometheus. The
> dashboard that consumes them lives in `wxops-gitops-infrastructure`; the toggle
> that sets these fields lives in the portal.

## Why CRDs and not annotations

`XTenantApp` today expresses monitoring as pod annotations — `prometheus.io/scrape`,
`prometheus.io/port`, `prometheus.io/path` (see the commented block in
[`examples/tenant-app/xr.yaml`](../examples/tenant-app/xr.yaml)).

**Those annotations do nothing.** They are a Prometheus *convention*, honoured only by a
`kubernetes_sd_config` job with relabel rules that read them. The platform runs
kube-prometheus-stack, whose `additionalScrapeConfigs` is empty — so nothing reads them
and the toggle silently no-ops.

The Prometheus Operator path is a CRD the Operator watches and turns into scrape config
for you. Beyond simply working, it buys things annotations cannot express at all:

| Capability | Annotations | Monitor CRD |
|---|---|---|
| Scrape at all (this platform) | ✗ | ✓ |
| Per-target `sampleLimit` | ✗ | ✓ |
| `metricRelabelings` — drop series at ingest | ✗ | ✓ |
| Per-target interval / timeout | ✗ | ✓ |
| TLS, auth, `honorLabels` | ✗ | ✓ |
| Schema-validated at apply time | ✗ | ✓ |
| Discoverable (`kubectl get servicemonitor -A`) | ✗ | ✓ |

`sampleLimit` matters most here. Prometheus runs with `sampleLimit`, `targetLimit` and
`labelLimit` all `0` — no guardrail anywhere. A limit set **by the composition** is one
tenants cannot opt out of, because they never author the object.

Lock-in is limited: Alloy can consume these same CRDs via
`prometheus.operator.servicemonitors`, so choosing them does not bind the platform to
the Operator forever.

## Why both kinds

The two are not interchangeable, and the difference is operational rather than cosmetic.

| | ServiceMonitor | PodMonitor |
|---|---|---|
| Targets | Endpoints behind a Service | Pods directly, by label |
| Needs a Service | **Yes** | No |
| Needs a named port | Yes (or `targetPort`) | No — container port by name or number |
| Scrapes a pod failing readiness | **No** | **Yes** |

That last row is the one that decides real incidents. A ServiceMonitor scrapes only
endpoints the Service considers `Ready`. A pod stuck failing its readiness probe drops
out of the endpoint list and **stops being scraped — exactly when its metrics matter
most.** A PodMonitor keeps scraping it.

So:

- **ServiceMonitor** is right for the ordinary load-balanced web service, and inherits
  the Service's view of healthy endpoints.
- **PodMonitor** is right for workloads with no Service at all — queue consumers, batch
  workers, anything scaffolded with `service.enabled: false` — and for cases where
  per-pod visibility through a readiness failure is worth more than endpoint semantics.

Supporting only ServiceMonitor would leave every Service-less workload unmonitorable.

## Proposed `spec.parameters.monitoring`

```yaml
monitoring:
  enabled: false          # master toggle
  kind: auto              # auto | ServiceMonitor | PodMonitor
  port: <int>             # no default — falls back to containerPort
  path: /metrics
  interval: 30s
  scrapeTimeout: 10s
  sampleLimit: 5000
  honorLabels: false
  metricRelabelings: []   # escape hatch for cardinality control
```

`port` deliberately carries **no XRD default** — `darlane.telemetryPort` sets that
precedent, with the fallback supplied by `_get` in KCL rather than by the schema.

### `kind: auto` resolution

| `service.enabled` | Emitted |
|---|---|
| `true` | ServiceMonitor |
| `false` | PodMonitor |

Auto keeps the common case configuration-free while leaving the override for teams that
know they want per-pod scraping despite having a Service. `monitoring.enabled: false`
emits neither.

## Emission requirements

Four things the generated manifest must get right. Each has failed silently in testing
elsewhere, so none is optional.

**1. The `release: kube-prometheus-stack` label.** Prometheus is deployed with
`serviceMonitorSelectorNilUsesHelmValues: true`, which makes the Operator filter
discovered monitors on the Helm release name. The release name comes from the directory
basename `base/observability-plane/kube-prometheus-stack/` in
`wxops-gitops-infrastructure`.

> **Cross-repo coupling worth knowing:** renaming that directory silently breaks every
> monitor this composition emits. There is no error — targets simply never appear.

**2. `selector.matchLabels` must include `app.kubernetes.io/component: app`.** The
Darlane twin's Services share `app.kubernetes.io/name` and `app.kubernetes.io/instance`
with the main app. Selecting on those alone scrapes the debug twin as well, mixing its
metrics into the service's own series.

**3. A named Service port, or `targetPort`.** A ServiceMonitor's `endpoints[].port`
references the Service port **by name**, and the Service emitted at
[`kcl/tenant-app/main.k:663`](../kcl/tenant-app/main.k) has an unnamed port. Two ways
out, and the choice is a genuine trade-off — see [What changes](#what-changes) below.

**4. Provider RBAC.** `providers/rbac-provider-kubernetes.yaml` enumerates every API
group composed `Object` manifests may touch, and `monitoring.coreos.com` is absent.
Without it every emitted monitor fails `forbidden` at reconcile time.

## Cardinality

The metric contract the templates will emit (`http_requests_total`,
`http_request_duration_seconds`, `http_requests_in_flight`) is low-cardinality **only if
the `path` label is the route pattern** — `/users/:id`, never `/users/12345`.

With no global limits configured, one tenant emitting raw URLs as labels degrades
Prometheus for every tenant on the cluster. Two defences, both belonging in the
composition rather than in tenant hands:

- `sampleLimit` defaulted by the composition and hard to remove
- `metricRelabelings` available as an escape hatch when a specific series misbehaves

## What changes

Classified against the [change taxonomy](../ROADMAP.md#change-taxonomy).

| Change | File | Tier |
|---|---|---|
| Add `monitoring` optional object with defaults | `package/tenant-app/xrd.yaml` | `safe` |
| Add ServiceMonitor, conditional emit | `kcl/tenant-app/main.k` | `safe` |
| Add PodMonitor, conditional emit | `kcl/tenant-app/main.k` | `safe` |
| Grant `monitoring.coreos.com` to the provider | `providers/rbac-provider-kubernetes.yaml` | prerequisite — not a composition change |
| Add `tenant-app` to the validation array | `.gitea/scripts/validate-packages.sh` | CI only |
| **Name the existing Service port `http`** | `kcl/tenant-app/main.k:663` | **`careful`** |

The `careful` row is the only one carrying risk. It edits the contents of a live composed
resource, so Crossplane applies an in-place patch. Adding a name to a *single-port*
Service is accepted by Kubernetes and restarts nothing — the Service spec changes, pods
do not. Low risk, but it is a mutation of something already running, and the taxonomy
says classify honestly.

**A zero-risk alternative exists.** A ServiceMonitor can target `targetPort: 8080`
instead of a port name, and a PodMonitor never needs one. Naming the port is the cleaner
long-term choice — it is what every Prometheus example assumes, and it survives a later
move to multiple ports — but it is a preference, not a requirement. If the port naming is
deferred, everything else here still works.

Release chores: bump `VERSIONS.yaml` (`tenant-app.package.current`), run `make kcl-sync`,
and commit `main.k` and `composition.yaml` together — `kcl-drift-check` is a pre-commit
hook.

## Open decisions

**Should the Darlane twin be scraped?** Requirement 2 above excludes it, which is right
for keeping a service's own metrics clean. But Darlane exists partly for A/B testing, and
comparing stable-versus-twin metrics is exactly what makes an A/B test measurable. A
future `darlane.monitoring` block emitting a second monitor scoped to
`component: darlane` would enable that, with a distinguishing label so the two series
never merge. Not in scope for the first pass.

**Should `monitoring` move to a shared KCL module?** `XTenantDatabase` will eventually
want the same block. The repo has no shared-library mechanism yet — see
[`kcl/README.md`](../kcl/README.md) — so the first implementation duplicates rather than
waits for one.

## See also

- [`tenant-app.md`](tenant-app.md) — the full `XTenantApp` schema
- [`ROADMAP.md`](../ROADMAP.md) — §0.7 for the work item, §Change taxonomy for the tiers
- [`multi-cluster.md`](multi-cluster.md) — per-cluster observability endpoints, later
