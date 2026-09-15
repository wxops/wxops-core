# Terraform, the Way This Repo Uses It

> This is not a Terraform tutorial — for the language itself, see
> [HashiCorp's own docs](https://developer.hashicorp.com/terraform/language). This page covers only
> the one pattern this repo uses, walking the real file `package/gitea-user/composition.yaml`.

**Table of Contents**
- [The pattern: one Workspace, inline HCL](#the-pattern-one-workspace-inline-hcl)
- [Reading the module](#reading-the-module)
- [How XR fields reach Terraform variables](#how-xr-fields-reach-terraform-variables)
- [How Terraform outputs become status](#how-terraform-outputs-become-status)
- [Where credentials come from](#where-credentials-come-from)
- [Next](#next)

---

## The pattern: one Workspace, inline HCL

Every `gitea-*` package and `random-password` composes exactly one object:
`tf.upbound.io/v1beta1 Workspace` — `provider-terraform`'s CRD. Its `spec.forProvider.module` field
holds an **entire Terraform module as a YAML string literal**. There's no separate `.tf` file, no
`terraform init` you run yourself: `provider-terraform` runs the whole plan/apply cycle inside the
cluster, against the module text in that field.

That's the whole pattern. No package in this repo runs a real `terraform` CLI outside the cluster,
and none references an external module registry.

## Reading the module

Open `package/gitea-user/composition.yaml`. Inside `spec.forProvider.module`, it's ordinary HCL:

```hcl
terraform {
  required_providers {
    gitea = {
      source  = "go-gitea/gitea"
      version = "~> 0.7.0"
    }
  }
}

variable "username" { type = string }
variable "admin" {
  type    = bool
  default = false
}

provider "gitea" {
  base_url = var.gitea_url
  token    = var.gitea_token
}

resource "gitea_user" "this" {
  username = var.username
  admin    = var.admin
}

output "user_id" { value = gitea_user.this.id }
```

Four sections, always in this order in every package here: `terraform { required_providers }`,
`variable` declarations, one `provider` block, then `resource` blocks and `output`s. If you know
HCL at all, this is unsurprising — the only repo-specific thing is that it lives inside a Kubernetes
manifest instead of a `.tf` file.

## How XR fields reach Terraform variables

The module's `variable`s get their values from `spec.forProvider.vars` — a list of `{key, value}`
pairs, positioned in the same order the composition's `patches` list expects:

```yaml
vars:
  - key: username
    value: placeholder   # overwritten by the patch below

patches:
  - type: FromCompositeFieldPath
    fromFieldPath: spec.parameters.username
    toFieldPath: spec.forProvider.vars[1].value   # index into the vars list
```

**This is the one fragile spot in the whole pattern.** The patch targets `vars[1]` by numeric
index — add or reorder a `vars` entry without checking every patch's index, and a value silently
lands on the wrong variable. When you add a field, add its `vars` entry at the **end** of the list,
so every existing index stays correct.

## How Terraform outputs become status

An `output` block becomes readable at `status.atProvider.outputs.<name>` once `terraform apply`
succeeds. A `ToCompositeFieldPath` patch copies it up onto the XR:

```yaml
- type: ToCompositeFieldPath
  fromFieldPath: status.atProvider.outputs.user_id
  toFieldPath: status.userId
  policy:
    fromFieldPath: Optional   # not present yet on the first reconcile — don't fail on that
```

`status.created`/`status.ready` are derived the same way: a regex match against that same output —
present and non-empty means the resource was created. Every package in this repo derives readiness
this way, for the reason explained in
[Reading status](../api-reference/README.md#reading-status).

An output marked `sensitive = true` in the module (like the generated password in `gitea-user`)
**never appears under `status.atProvider.outputs`** — it's routed to a Kubernetes Secret instead,
via `writeConnectionSecretToRef`. Never write a patch trying to read a sensitive output from status;
it won't be there.

## Where credentials come from

`credentialsSecretRef` on the XR points at a Kubernetes Secret formatted as `.tfvars` — that's what
`varFiles: [{source: SecretKey, ...}]` in the module expects. See
[setup — create a credentials secret](../user-guide/setup.md#2--create-a-credentials-secret) for the
exact format.

## Next

- [Crossplane in five minutes](01-crossplane-in-5-minutes.md), if you haven't yet
- [Your first change](04-your-first-change.md) — a guided edit to `gitea-team`, using exactly this
  pattern
