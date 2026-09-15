# Release Notes

Hand-written notes for W'xOps Core releases. A release is named by the day it is cut —
`release-YYYY-MM-DD` (UTC), with `.2` for a second one that day — not by a version number.

---

## What a release name means — and what it doesn't

Core and the portal release independently, so neither's release number can say anything about the
other. What they share is the **API**: the portal writes `platform.wxops.cloud/v1alpha1` XRs and
reads their `status`. That contract has its own version and its own guard:

| Axis | Example | Changes | Protected by |
|---|---|---|---|
| **API version** | `platform.wxops.cloud/v1alpha1` | Almost never | `tests/api_compat.py` — additive-only against the last release |
| **Release** | `release-2026-09-11` | Every release | `make release` — pins `VERSIONS.yaml` and `package/install/` |

A portal build pins an API version, never a core release. Any core release serving that version
works with it, and `tests/api_compat.py` is what keeps that true: Crossplane has no conversion
between XRD versions, so a released schema can only grow.

Releases before the switch kept their semver tags (`v0.1.0` … `v0.4.0`); their notes stay here as
history.

---

## When notes are required

`make release` classifies every change against the last release, using the tiers
[`tests/README.md`](../tests/README.md#test-api-compat--a-released-api-only-grows) defines:

| Tier | Example | Notes |
|---|---|---|
| `safe` | New optional field, new status field, new conditional resource | Optional |
| `careful` | Changed default, changed content of a composed resource | **Required** — `make release` refuses without them |
| `breaking` | Removed field, renamed composed resource, selector change | **Required**, and only possible with an entry in [`tests/api-compat-allow.yaml`](../tests/api-compat-allow.yaml) |

For a `safe` release, skip the file unless an operator needs to know something. CI already
publishes the package table and the git-cliff changelog without it.

## How to write them

```bash
make release-notes                  # today's name, or VERSION=release-YYYY-MM-DD
$EDITOR release-notes/release-YYYY-MM-DD.md
make release                        # same day, or pass the same VERSION
```

`make release-notes` pre-fills **Compatibility** from `tests/api_compat.py`. Keep the table; the
prose under it is yours — explain every row that is not `safe`, then delete the reference block at
the bottom. `make release` stages `release-notes/` in the release commit, so there is nothing to
commit separately.

Notes are matched by file name. A file scaffolded on one day and released on the next needs the
same `VERSION` passed to both commands.

## What CI does with this directory

On a `release-*` tag, [`.github/workflows/publish-packages.yaml`](../.github/workflows/publish-packages.yaml)
publishes the release with:

| Part | Source |
|---|---|
| Your notes | `release-notes/<release>.md`, if present |
| Package table | `release-state.py summary` — which packages were rebuilt, their API versions, their change tier |
| Changelog | `git-cliff --current` |

The section structure lives in [`template.md`](template.md).
