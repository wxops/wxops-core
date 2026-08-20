#!/usr/bin/env python3
"""
Structural check on the manifests *inside* composed Objects — best-effort.

`make lint` runs kubeconform over package/, which validates the XRDs and
Compositions themselves but never the CNPG Cluster, ExternalSecret, IngressRoute
or ServiceMonitor a composition actually produces. Those are templated inside
spec.forProvider.manifest and reach the cluster unvalidated.

This is deliberately a FILTER, NOT A GATE, and the naming reflects that:

  • The schemas come from the public datreeio CRDs-catalog, not from the operator
    versions pinned in CLAUDE.md. The catalogue tracks upstream latest, which is
    effectively a superset of your pinned versions because APIs add fields over
    time. So the realistic failure mode is a FALSE PASS: you template a field
    that exists upstream but not in your pinned CNPG, this says valid, and the
    cluster rejects it.
  • Kinds the catalogue does not cover (provider-sql's Role and ProviderConfig)
    cannot be checked at all. Those are reported as a coverage gap, and never
    fail the build — a permanently-red check is a check people learn to ignore.

What it does catch, reliably and cheaply: structural mistakes in templated YAML —
a misspelled field, a string where an int belongs, wrong nesting.

Version-independent guarantees about fields we actually depend on live in
tests/invariants.py instead, as field contracts. Authoritative validation needs
either the real pinned CRDs or a live cluster; see tests/README.md.

The catalogue ref is PINNED below. An unpinned schema source makes the gate
non-reproducible — upstream could change what CI accepts with no commit here.

Usage:
    python3 tests/structural.py
"""
from __future__ import annotations

import json
import subprocess
import sys
import tempfile
from collections import Counter
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent / "lib"))
import render as R  # noqa: E402
import yaml  # noqa: E402

# Pinned deliberately. Bump alongside the reference stack in CLAUDE.md, as a
# reviewable commit — never track a moving branch from a CI gate.
CATALOG_REF = "52b0261318acc7dd0b66e032759b1f218216b980"

SCHEMA_LOCATIONS = [
    "default",
    f"https://raw.githubusercontent.com/datreeio/CRDs-catalog/{CATALOG_REF}/"
    "{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json",
]


def wrapped_manifests() -> list[tuple[str, dict]]:
    """(source_label, manifest) for every manifest inside a composed Object."""
    out = []
    for package, case, case_dir in R.discover():
        golden = case_dir / "expected.yaml"
        if golden.exists():
            docs = R.load_docs(golden.read_text())
        else:
            ok, rendered, _ = R.render(case_dir, package)
            if not ok:
                continue
            docs = R.load_docs(rendered)
        for d in docs:
            if d.get("kind") != "Object":
                continue
            m = ((d.get("spec") or {}).get("forProvider") or {}).get("manifest")
            if isinstance(m, dict) and m.get("kind"):
                out.append((f"{package}/{case}", m))
    return out


def main() -> int:
    manifests = wrapped_manifests()
    if not manifests:
        print(f"{R.RED}no wrapped manifests found{R.RESET} — run make test-update first")
        return 1

    kinds = Counter(f"{m.get('apiVersion')}/{m.get('kind')}" for _, m in manifests)
    print(f"structural check (best-effort) — {len(manifests)} wrapped manifest(s), "
          f"{len(kinds)} distinct kind(s)")
    print(f"{R.DIM}catalogue pinned at {CATALOG_REF[:12]}; a pass here is not proof of "
          f"correctness against your pinned operator versions{R.RESET}\n")

    tmp = Path(tempfile.mkdtemp())
    # One file per manifest so kubeconform reports a usable location, and so a
    # missing name (which kubeconform rejects outright) is attributable.
    paths = []
    for i, (src, m) in enumerate(manifests):
        p = tmp / f"{i:03d}-{m['kind']}.yaml"
        p.write_text(R.dump_all([m]))
        paths.append((p, src, m))

    # -ignore-missing-schemas turns "no published schema" into statusSkipped
    # rather than statusError, so a genuine schema violation stays
    # distinguishable from a kind the catalog simply does not cover. Skips are
    # still reported below — they are a coverage gap, not a pass.
    #
    # -summary is deliberately NOT passed: it suppresses the per-resource
    # entries, leaving only counts, and we need to know *which* kinds were
    # skipped in order to report the gap per kind.
    # -verbose is required: without it kubeconform reports only failures, so
    # valid and skipped resources are invisible and coverage cannot be measured.
    # -ignore-missing-schemas keeps uncovered kinds as skipped rather than
    # errors, so a real violation stays distinguishable from a coverage gap.
    cmd = ["kubeconform", "-output", "json", "-strict", "-verbose",
           "-ignore-missing-schemas"]
    for loc in SCHEMA_LOCATIONS:
        cmd += ["-schema-location", loc]
    cmd += [str(p) for p, _, _ in paths]

    proc = subprocess.run(cmd, capture_output=True, text=True)
    try:
        report = json.loads(proc.stdout)
    except json.JSONDecodeError:
        print(f"{R.RED}kubeconform produced no parsable output{R.RESET}")
        print(proc.stdout[:500] or proc.stderr[:500])
        return 1

    by_path = {str(p): (src, m) for p, src, m in paths}
    invalid, skipped = [], []
    n_valid = 0
    for res in report.get("resources", []):
        status = res.get("status")
        src, m = by_path.get(res.get("filename", ""), ("?", {}))
        ident = f"{m.get('apiVersion')}/{m.get('kind')}"
        if status in ("statusInvalid", "statusError"):
            invalid.append((src, ident, res.get("msg", "")))
        elif status == "statusSkipped":
            skipped.append((src, ident))
        else:
            n_valid += 1

    skipped_kinds = {i for _, i in skipped}
    for ident, n in sorted(kinds.items()):
        mark = f"{R.YELLOW}no schema{R.RESET}" if ident in skipped_kinds else f"{R.GREEN}validated{R.RESET}"
        print(f"  {mark:<22} {ident} {R.DIM}×{n}{R.RESET}")

    print()
    if invalid:
        print(f"{R.RED}{len(invalid)} invalid manifest(s){R.RESET}\n")
        for src, ident, msg in invalid:
            print(f"  {R.RED}{ident}{R.RESET} in {src}\n      {msg}")
        return 1

    print(f"{R.GREEN}valid{R.RESET}: {n_valid}   "
          f"{R.YELLOW}no schema published{R.RESET}: {len(skipped)}   "
          f"{R.RED}invalid{R.RESET}: {len(invalid)}")
    if skipped:
        gaps = sorted({i for _, i in skipped})
        print(f"\n{R.YELLOW}Coverage gap — no published schema, not checked:{R.RESET}")
        for g in gaps:
            print(f"  {R.DIM}{g}{R.RESET}")
        print(f"{R.DIM}Not a failure. Field-level guarantees for these live in "
              f"tests/invariants.py.{R.RESET}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
