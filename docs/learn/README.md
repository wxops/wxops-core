# Learn — for contributors new to Crossplane, Terraform or KCL

> `CONTRIBUTING.md` assumes you can already read a `Composition`. These four short pages fill the
> gap before that, each teaching one concept against a real file from this repo — not a generic
> tutorial. Read only what you're missing; skip the rest.

| # | Page | Read if… |
|---|---|---|
| 1 | [Crossplane in five minutes](01-crossplane-in-5-minutes.md) | You've never worked with Crossplane — what an XRD, a Composition and an XR are, walked through `gitea-user` end to end |
| 2 | [Terraform, the way this repo uses it](02-terraform-here.md) | You're about to touch a `gitea-*` package — how the inline-HCL `Workspace` pattern works here |
| 3 | [KCL, the way this repo uses it](03-kcl-here.md) | You're about to touch `platform-database-clusters`, `tenant-database` or `tenant-app` — this repo's KCL idioms, on a real slice of code |
| 4 | [Your first change](04-your-first-change.md) | You've read what you needed above and want to make an actual edit, start to finish |

Every package, mapped to which of these to read first:

| Package | Technique | Read | Composition source |
|---|---|---|---|
| `gitea-user`, `gitea-org`, `gitea-team`, `gitea-repository` | Terraform (inline HCL) | 1, 2 | `package/<name>/composition.yaml` |
| `random-password` | Terraform (inline HCL) | 1, 2 | `package/random-password/composition.yaml` |
| `platform-database-clusters`, `tenant-database`, `tenant-app` | KCL | 1, 3 | `kcl/<name>/main.k` |

Once you're past these, the workflow doc is [`CONTRIBUTING.md`](../../CONTRIBUTING.md); the full
map of every other doc is [`docs/README.md`](../README.md).
