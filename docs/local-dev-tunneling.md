# Local dev tunneling (Telepresence / Mirrord)

`tenant-app` deploys workloads with stable, predictable identifiers — the
`Deployment`, `Service`, and `Ingress` are all named `<appName>` in
`<namespace>`, and selector labels are always:

```yaml
app.kubernetes.io/name: <appName>
app.kubernetes.io/instance: <appName>
```

This is enough for [Telepresence](https://www.telepresence.io/) and
[Mirrord](https://mirrord.dev/) to attach to a workload without any extra
annotations from the platform side. Neither tool needs to be wired into the
Composition — they operate purely against the `Deployment`/`Service` that
`tenant-app` already produces.

## Recommended: target the `devSpace` twin, not the production pod

Set `devSpace.enabled: true` (see [tenant-app.md](tenant-app.md#devspace-debug-twin-deployment))
to get a second `<appName>-dev` Deployment that shares the main Deployment's
`image`/`env`/`envFrom` — including any `secretsFrom`-managed Vault/database
secrets and network access — but is scaled to `0` replicas and has **no
`Service`/`Ingress`** (zero external exposure).

```bash
# Scale the dev twin up on-demand
kubectl -n <namespace> scale deployment/<appName>-dev --replicas=1

# Point Telepresence/Mirrord at it (examples below use deployment/<appName>-dev)
# ...debug...

# Scale back down when done
kubectl -n <namespace> scale deployment/<appName>-dev --replicas=0
```

Why this is preferable to attaching directly to the production
`deployment/<appName>`:

- **Zero traffic risk** — `<appName>-dev` has no `Service`/`Ingress`, so
  there's nothing to steal traffic *from*. Telepresence's intercept and
  Mirrord's `--steal` only affect this throwaway pod.
- **Same secrets/database access, isolated blast radius** — you get
  identical Vault-backed env vars and DB connectivity as production, in a
  pod that's scaled to zero except when you're actively using it.
- **No probe interference** — the production `Deployment`'s
  `livenessProbe`/`readinessProbe` (see
  [Golden Path Contract](tenant-app.md#golden-path-contract)) are never
  affected, since you're not touching `deployment/<appName>` at all.

If `devSpace` isn't enabled for an app yet, both tools can still target
`deployment/<appName>` directly — see the caveats at the end of each section
below.

## Telepresence — full traffic intercept

```bash
# Connect to the cluster (routes cluster-internal traffic through the tunnel)
telepresence connect --namespace <namespace>

# Intercept the dev twin — traffic routed to it is rerouted to localhost:<port>
telepresence intercept <appName>-dev --port <containerPort>:<containerPort> --namespace <namespace>

# Run your app locally on <containerPort>; it now has the dev twin's network
# identity and can reach in-cluster Vault/ESO-synced Secrets, the tenant
# database, and any other Service in <namespace> as if it were that pod.

# When done
telepresence leave <appName>-dev-<namespace>
telepresence quit
```

To pull the resolved env vars (including `envFrom`-sourced secrets) to a
local `.env` file instead of fully intercepting:

```bash
telepresence intercept <appName>-dev --port <containerPort>:<containerPort> \
  --namespace <namespace> --env-file .env.local
```

**Caveat if targeting `deployment/<appName>` directly** (no `devSpace`):
this *does* steal live traffic from the production `Service`/`Ingress`, and
your local process must also serve `/healthz`/`/readyz` (or whatever
`probes.*.path` you've configured) so the `Service` doesn't get marked
unready once the intercept ends.

## Mirrord — per-process traffic mirroring

```bash
mirrord exec --target deployment/<appName>-dev --target-namespace <namespace> -- <your-run-command>

# e.g. for a Node app:
mirrord exec --target deployment/<appName>-dev --target-namespace <namespace> -- npm run dev
```

This automatically picks up:

- `env` and `envFrom` (including any `secretsFrom`-managed Secrets) from the
  target container's spec.
- Network access to the tenant database and any other in-namespace Service,
  exactly as the pod would have it.

Mirrord defaults to mirroring (read-only) — traffic to `<appName>-dev` is
copied to your local process, not redirected. Add `--steal` to redirect it
instead; since `<appName>-dev` has no `Service`/`Ingress`, there's no live
traffic to steal unless something else in-cluster talks to it directly.

**Caveat if targeting `deployment/<appName>` directly** (no `devSpace`): add
`--steal` only if you intend to take over real production requests for that
pod — prefer mirroring (the default) in that case.

## Choosing between them

| | Telepresence | Mirrord |
|---|---|---|
| Default mode | Intercept (redirects traffic) | Mirrors traffic (read-only) |
| Setup | Cluster-side traffic-manager + local daemon | No cluster-side component |
| Best for | "Replace the pod with my laptop" debugging | Quick "run with prod-like env/network" without disrupting any live pod |

Both work against `<appName>-dev` (or `<appName>` directly, with the caveats
above) without further changes to the XR — pick whichever matches your
team's existing tooling.
