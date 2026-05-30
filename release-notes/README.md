# Release Notes

This directory holds hand-written release notes for versions that need human context beyond what git-cliff generates automatically.

---

## Two paths — choose one

### Let CI handle it (default)

For routine releases — bug fixes, dependency bumps, refactors, chore commits — do nothing here. CI generates the release body from git-cliff and publishes it directly as the Gitea release page.

### Write your own (significant releases)

Write a `<version>.md` when automated changelog alone is not enough for operators to understand what changed and what they need to do. Clear signals that a file is warranted:

| Signal | Example |
|---|---|
| **Breaking change** | XRD field renamed, API version removed, incompatible Composition change |
| **Migration required** | In-cluster steps needed before or after upgrading |
| **Major milestone** | First stable API (`v1alpha1` → `v1beta1`), architectural pivot |
| **Deprecation notice** | A served API version marked for future removal |
| **Operator-facing behaviour change** | Default values changed, reconciliation logic altered |

If you are unsure — skip it. A missing file produces a clean, correct release. An empty or boilerplate file adds noise.

---

## How to write release notes

```bash
# Scaffold from template (populates Highlights / Upgrade notes / Known issues
# and appends a git-cliff reference block showing upcoming commits)
make release-notes VERSION=vX.Y.Z

# Edit the file — fill in the sections, remove the reference block
$EDITOR release-notes/vX.Y.Z.md

# Commit before releasing
git add release-notes/vX.Y.Z.md
git commit -m "chore: add release notes for vX.Y.Z"

# Release as normal — CI will prepend your file to the cliff changelog
make release VERSION=vX.Y.Z
```

---

## What CI does with this directory

| Condition | Gitea release body |
|---|---|
| `release-notes/<version>.md` **exists** | Your file + `---` separator + git-cliff changelog |
| `release-notes/<version>.md` **absent** | git-cliff changelog only |

The section structure lives in [`template.md`](template.md).
