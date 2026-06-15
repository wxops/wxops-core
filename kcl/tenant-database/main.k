"""
XTenantDatabase — KCL composition source.

Inputs (via option("params").oxr.spec.parameters):
  tier                string    Platform-defined cluster pool to provision on. One of
                                 the keys of _clusterTierMap below (currently: "shared").
                                 Default: "shared". Ignored if clusterRef/clusterNamespace
                                 are set explicitly.
  clusterRef          string    CNPG cluster name (XPlatformDatabaseCluster.clusterName).
                                 Used as spec.cluster.name on the CNPG Database CR and as
                                 the name of the per-cluster provider-sql ProviderConfig
                                 (created by platform-database-clusters) referenced by the Role below.
                                 Defaults to the cluster mapped from `tier` if unset.
  clusterNamespace    string    Namespace where the CNPG cluster (and all resources
                                 composed by this XR) live. Defaults to the namespace
                                 mapped from `tier` if unset.
  dbName              string    PostgreSQL database name to create.
  owner               string    Team/project identifier (e.g. "rocket-team"). Scopes role name + Vault path.
  extensions          [string]  PostgreSQL extensions to enable. Default: [].
  databaseReclaimPolicy string  CNPG Database.spec.databaseReclaimPolicy: "delete" | "retain".
                                 Default: "retain" (protects the database — and its
                                 owning role — from XR deletion; both survive and must
                                 be cleaned up manually if the tenant is decommissioned).
                                 "delete" drops the database on XR deletion, which also
                                 lets the owning role be dropped. A ClusterUsage
                                 (tenant-role-db-usage) orders this: the Role's DROP ROLE
                                 is blocked until the Database's DROP DATABASE has
                                 completed, then replayed — avoiding the "role ... cannot
                                 be dropped because some objects depend on it" (2BP01)
                                 race that parallel deletion would otherwise cause.
  vaultSecretStoreName string   ESO ClusterSecretStore name. Default: "vault-cluster-store".

Design — provider-sql Role for continuous per-tenant role reconciliation:
  - ESO generates the role password once and bundles it into Secret
    {roleName}-connection-creds in {clusterNamespace}. refreshPolicy:
    CreatedOnce means ESO only writes this Secret if it doesn't already
    exist — see refreshPolicy/deletionPolicy notes near esoRefreshPolicy
    below.
  - A postgresql.sql.crossplane.io/v1alpha1 Role (tenant-sql-role) is
    provisioned via the per-cluster provider-sql ProviderConfig named
    clusterRef (created by platform-database-clusters from its superuser creds Secret).
    Role.spec.forProvider.passwordSecretRef points at
    {roleName}-connection-creds, read only at Create() time — provider-sql
    never re-applies password changes on an existing role. ⚠ If
    tenant-sql-role and tenant-conn-bundle's Secret are created in the same
    reconcile (most likely after databaseReclaimPolicy: "delete" + XR
    delete/recreate, which destroys and rebuilds the Role), provider-sql can
    read the Secret before ESO has written the generated password
    (informer-cache race), creating the role with no usable password —
    permanently, since Update() never re-applies it. Prefer
    databaseReclaimPolicy: "retain" so the Role survives XR recreation; if
    this happens under "delete", an operator must manually fix the role's
    password (ALTER ROLE ... PASSWORD) to match {roleName}-connection-creds.
  - The database itself is a native postgresql.cnpg.io/v1 Database CR
    (spec.cluster.name = clusterRef, spec.owner = roleName, spec.extensions),
    reconciled by CNPG directly. CNPG retries until the role exists.
  - PushSecret syncs the connection bundle to Vault once (refreshInterval:
    "0" — the password never changes after creation under CreatedOnce, so
    there's nothing to re-push periodically; spec changes still trigger a
    re-sync). Consuming the Vault entry (tenant/{owner}/{dbName}/connection-creds)
    into an app namespace is intentionally NOT done here — that's a
    tenant/GitOps concern (e.g. tenant-app's externalSecrets toggle), keeping
    this package focused on provisioning the role/database/credentials only.

Password rotation is intentionally NOT implemented here — provider-sql never
re-applies password changes to an existing role, so any rotation must also
converge Postgres itself. That's a platform-level concern (e.g. Vault
Database Secrets Engine dynamic/rotated roles), tracked separately. This
package only handles initial creation and management of the role/database and
their connection-creds Secret.

Composed resources:
  tenant-pwd-gen       generators.external-secrets.io/v1alpha1  Password       — 32-char random password.
  tenant-conn-bundle   external-secrets.io/v1              ExternalSecret — {roleName}-connection-creds.
  tenant-sql-role      postgresql.sql.crossplane.io/v1alpha1     Role           — per-tenant role + password (provider-sql).
  cnpg-database        postgresql.cnpg.io/v1                     Database       — PostgreSQL database + extensions.
  tenant-push-secret   external-secrets.io/v1alpha1             PushSecret     — pushes bundle to Vault (once).

Vault path written: tenant/{owner}/{dbName}/connection-creds
"""

oxr = option("params").oxr
params = oxr.spec.parameters
uid = oxr.metadata.uid
short = uid[:8:]

# Platform-defined cluster pools — extend this map as new tiers/clusters
# come online. clusterRef/clusterNamespace, if set explicitly, always win.
_clusterTierMap = {
    "shared" = {clusterRef = "cluster-a", clusterNamespace = "cnpg-system"}
}

tier = params.tier if "tier" in params else "shared"
_tierDefaults = _clusterTierMap[tier]

clusterRef = params.clusterRef if "clusterRef" in params else _tierDefaults.clusterRef
clusterNs = params.clusterNamespace if "clusterNamespace" in params else _tierDefaults.clusterNamespace
dbName = params.dbName
owner = params.owner
extensions = params.extensions if "extensions" in params else []
databaseReclaimPolicy = params.databaseReclaimPolicy if "databaseReclaimPolicy" in params else "retain"
vaultStore = params.vaultSecretStoreName if "vaultSecretStoreName" in params else "vault-cluster-store"

# Resource names — all derived from owner + dbName for human readability and
# uniqueness within a shared clusterNamespace.
roleName = owner + "-" + dbName
pwdGenName = roleName + "-pwd-gen"
connSecretName = roleName + "-connection-creds"
vaultPath = owner + "/" + dbName + "/connection-creds"
endpoint = clusterRef + "-rw." + clusterNs + ".svc.cluster.local"
connStr = "postgresql://" + roleName + ":{{ .password }}@" + endpoint + ":5432/" + dbName

# refreshInterval: "0" = stable, ESO never regenerates the password on its
# own schedule (only at initial creation — see refreshPolicy below).
esoRefreshInterval = "0"

# refreshPolicy: "CreatedOnce" tells ESO to write {connSecretName} only if it
# does not already exist yet — it will not re-invoke the Password generator or
# overwrite an existing Secret. This only holds across XR delete+recreate if
# the ExternalSecret CR itself (which tracks "have I created it before") also
# survives — see _objDeletionPolicy below. Paired with target.deletionPolicy
# and _objDeletionPolicy, this makes delete+recreate of the XR behave
# correctly for both reclaim policies:
#   - "retain": the Secret survives XR deletion (target.deletionPolicy:
#     Retain), and so does the ExternalSecret/Password-generator CRs
#     (_objDeletionPolicy: Orphan); on recreate, ESO's CreatedOnce state is
#     intact, finds the Secret already exists, and leaves it alone — the
#     password keeps matching the adopted Postgres role's actual password (no
#     manual ALTER ROLE ... PASSWORD needed).
#   - "delete": the Secret and the ExternalSecret/Password-generator CRs are
#     all deleted (target.deletionPolicy: Delete, _objDeletionPolicy: Delete);
#     on recreate nothing exists, so ESO generates a fresh password as normal
#     — a true clean Create().
esoRefreshPolicy = "CreatedOnce"

# target.deletionPolicy for {connSecretName}: mirrors databaseReclaimPolicy so
# "delete" really does remove everything (Secret included), while "retain"
# keeps the Secret around for the CreatedOnce check above. ESO's CRD default
# is "Retain" — set explicitly here for both branches for auditability.
_connSecretDeletionPolicy = "Delete" if databaseReclaimPolicy == "delete" else "Retain"

# spec.deletionPolicy for the tenant-pwd-gen / tenant-conn-bundle Object
# wrappers below. On XR deletion Crossplane deletes these Object CRs, and by
# default ("Delete") provider-kubernetes also deletes the underlying
# Password-generator / ExternalSecret CRs they wrap (named {pwdGenName} /
# {roleName}-conn-es — both stable, NOT derived from the XR's UID). Deleting
# the ExternalSecret CR destroys its CreatedOnce "already created" state, so
# on recreate a brand-new ExternalSecret CR finds the retained
# {connSecretName} Secret "orphaned" and — per ESO's
# ownership-deletion-policy semantics — adopts AND overwrites it with a
# freshly-generated password, regardless of CreatedOnce/target.deletionPolicy.
#   - "retain" -> "Orphan": the underlying Password generator and
#     ExternalSecret CRs survive XR deletion, so on recreate the new wrapper
#     finds them already present with intact CreatedOnce state — the admin
#     keeps full control of when/whether {connSecretName} ever changes.
#   - "delete" -> "Delete": everything is torn down together for a true clean
#     Create() on recreate.
_objDeletionPolicy = "Orphan" if databaseReclaimPolicy == "retain" else "Delete"

# ── ESO Password Generator ─────────────────────────────────────────
# Lives in {clusterNamespace} so the ExternalSecret below (same namespace)
# can reference it via generatorRef.
_pwd_gen = {
    apiVersion = "kubernetes.crossplane.io/v1alpha2"
    kind = "Object"
    metadata = {
        name = short + "-pwd-gen"
        annotations = {
            "crossplane.io/composition-resource-name" = "tenant-pwd-gen"
        }
    }
    spec = {
        deletionPolicy = _objDeletionPolicy
        providerConfigRef = {name = "default"}
        forProvider = {
            manifest = {
                apiVersion = "generators.external-secrets.io/v1alpha1"
                kind = "Password"
                metadata = {name = pwdGenName, namespace = clusterNs}
                spec = {
                    length = 32
                    digits = 8
                    symbols = 0
                    symbolCharacters = ""
                    noUpper = False
                    allowRepeat = False
                }
            }
        }
    }
}

# ── ESO ExternalSecret: connection bundle ──────────────────────────
# Creates Secret {roleName}-connection-creds in {clusterNamespace}.
# tenant-managed-role points CNPG's managed.roles[].passwordSecret at this
# Secret so CNPG creates/alters the role and keeps its password in sync.
# PushSecret syncs the whole bundle to Vault.
_conn_bundle = {
    apiVersion = "kubernetes.crossplane.io/v1alpha2"
    kind = "Object"
    metadata = {
        name = short + "-conn-bundle"
        annotations = {
            "crossplane.io/composition-resource-name" = "tenant-conn-bundle"
        }
    }
    spec = {
        deletionPolicy = _objDeletionPolicy
        providerConfigRef = {name = "default"}
        forProvider = {
            manifest = {
                apiVersion = "external-secrets.io/v1"
                kind = "ExternalSecret"
                metadata = {name = roleName + "-conn-es", namespace = clusterNs}
                spec = {
                    refreshInterval = esoRefreshInterval
                    refreshPolicy = esoRefreshPolicy
                    dataFrom = [{
                        sourceRef = {
                            generatorRef = {
                                apiVersion = "generators.external-secrets.io/v1alpha1"
                                kind = "Password"
                                name = pwdGenName
                            }
                        }
                    }]
                    target = {
                        name = connSecretName
                        creationPolicy = "Owner"
                        deletionPolicy = _connSecretDeletionPolicy
                        template = {
                            engineVersion = "v2"
                            data = {
                                username = roleName
                                password = "{{ .password }}"
                                endpoint = endpoint
                                port = "5432"
                                database = dbName
                                connectionString = connStr
                            }
                        }
                    }
                }
            }
        }
    }
}

# ── tenant-sql-role: provider-sql Role for this tenant's database ──────────
# postgresql.sql.crossplane.io/v1alpha1 Role, reconciled via the per-cluster
# ProviderConfig named clusterRef (created by platform-database-clusters from its
# superuser creds Secret). passwordSecretRef points at {connSecretName} and is
# applied only at Create() time — provider-sql does not re-apply password
# changes on an existing role (see "Password rotation" note in the docstring).
#
# ⚠ Known provider-sql race: Create() reads
# {connSecretName} for the initial password. If this Role CR and
# tenant-conn-bundle's Secret are created in the same reconcile, provider-sql
# can read the Secret before ESO has written the generated password
# (informer-cache lag), creating the role with NO usable password — and since
# Update() never re-applies passwords, it stays broken until an operator runs
# ALTER ROLE manually. This is most likely after databaseReclaimPolicy:
# "delete" + XR delete/recreate, where tenant-sql-role is destroyed and
# rebuilt from scratch. Mitigation: prefer databaseReclaimPolicy: "retain" so
# the Role (and its working password) survives XR recreation; if "delete" is
# used and login fails after a recreate, check the role's password manually
# (ALTER ROLE ... PASSWORD) against {connSecretName}.
#
# deletionPolicy follows databaseReclaimPolicy, same reasoning as
# _pushDeletionPolicy below: "retain" keeps the Database CR (and its
# underlying Postgres database) alive, so this Role must NOT run DROP ROLE on
# XR deletion — it would hit 2BP01 against the retained database and get
# stuck Deleting. "Orphan" removes the Crossplane Role resource without
# touching the Postgres role, matching the retained database it owns.
# "delete" -> "Delete" (drop the role along with the dropped database).
_roleDeletionPolicy = "Orphan" if databaseReclaimPolicy == "retain" else "Delete"
_sql_role = {
    apiVersion = "kubernetes.crossplane.io/v1alpha2"
    kind = "Object"
    metadata = {
        name = short + "-sql-role"
        annotations = {
            "crossplane.io/composition-resource-name" = "tenant-sql-role"
        }
    }
    spec = {
        providerConfigRef = {name = "default"}
        forProvider = {
            manifest = {
                apiVersion = "postgresql.sql.crossplane.io/v1alpha1"
                kind = "Role"
                metadata = {name = roleName}
                spec = {
                    deletionPolicy = _roleDeletionPolicy
                    providerConfigRef = {name = clusterRef}
                    forProvider = {
                        privileges = {login = True}
                        passwordSecretRef = {
                            namespace = clusterNs
                            name = connSecretName
                            key = "password"
                        }
                    }
                }
            }
        }
    }
}

# ── CNPG Database CR ────────────────────────────────────────────────
# Native postgresql.cnpg.io/v1 Database — must live in {clusterNamespace}
# (spec.cluster.name is a same-namespace reference). CNPG creates the
# database (and extensions) once spec.owner exists as a role.
# databaseReclaimPolicy (default "retain") — the database (and its owning
# role, tenant-sql-role below) survive XR deletion and must be cleaned up
# manually if the tenant is decommissioned. Set params.databaseReclaimPolicy
# to "delete" to have CNPG drop the database on XR deletion instead; the
# ClusterUsage below (_cluster_usage) orders the Role's DROP ROLE to run only
# after this Database's DROP DATABASE has completed, avoiding the 2BP01
# parallel-deletion race.
_dbSpec = {
    cluster = {name = clusterRef}
    name = dbName
    owner = roleName
    databaseReclaimPolicy = databaseReclaimPolicy
} | ({"extensions": [{"name": ext, "ensure": "present"} for ext in extensions]} if extensions else {})

_cnpg_database = {
    apiVersion = "kubernetes.crossplane.io/v1alpha2"
    kind = "Object"
    metadata = {
        name = short + "-cnpg-database"
        annotations = {
            "crossplane.io/composition-resource-name" = "cnpg-database"
        }
    }
    spec = {
        providerConfigRef = {name = "default"}
        forProvider = {
            manifest = {
                apiVersion = "postgresql.cnpg.io/v1"
                kind = "Database"
                metadata = {name = roleName, namespace = clusterNs}
                spec = _dbSpec
            }
        }
    }
}

# ── ClusterUsage: order Role deletion after Database deletion ─────
# Only composed when databaseReclaimPolicy == "delete" (when "retain",
# tenant-sql-role's deletionPolicy is "Orphan" — it never runs DROP ROLE, so
# there is nothing to order).
#
# protection.crossplane.io/v1beta1 ClusterUsage: "of" (tenant-sql-role's
# Object) cannot be deleted while "by" (cnpg-database's Object) still exists.
# On XR deletion Crossplane deletes all composed resources in parallel; this
# blocks the Role Object's deletion (and therefore its DROP ROLE) with a
# finalizer until the Database Object has actually been deleted (DROP
# DATABASE done). replayDeletion: true re-triggers the blocked Role deletion
# once that finalizer is lifted, so DROP ROLE then runs against a database
# that's already gone — fixing the "role ... cannot be dropped because some
# objects depend on it" (2BP01) parallel-deletion race documented above.
_cluster_usage = {
    apiVersion = "protection.crossplane.io/v1beta1"
    kind = "ClusterUsage"
    metadata = {
        name = short + "-role-db-usage"
        annotations = {
            "crossplane.io/composition-resource-name" = "tenant-role-db-usage"
        }
    }
    spec = {
        of = {
            apiVersion = "kubernetes.crossplane.io/v1alpha2"
            kind = "Object"
            resourceRef = {name = short + "-sql-role"}
        }
        by = {
            apiVersion = "kubernetes.crossplane.io/v1alpha2"
            kind = "Object"
            resourceRef = {name = short + "-cnpg-database"}
        }
        reason = "Block DROP ROLE until DROP DATABASE has completed, avoiding the 2BP01 parallel-deletion race."
        replayDeletion = True
    }
}

# ── ClusterUsage: order connection-secret deletion after Role deletion ────
# Only composed when databaseReclaimPolicy == "delete" (when "retain",
# tenant-conn-bundle's deletionPolicy is "Orphan" — nothing to order).
#
# provider-sql's reconciler calls Observe() before Delete() on every pass,
# and Observe() unconditionally reads Role.spec.forProvider.passwordSecretRef
# ({connSecretName}). If tenant-conn-bundle (and the {connSecretName} Secret
# it owns) is deleted before tenant-sql-role finishes deleting, Observe()
# permanently fails with "cannot get password secret: ... not found" —
# Delete() (DROP ROLE) never runs, and the Role's finalizer never clears,
# deadlocking the Object/Role CR in Terminating forever (confirmed live).
#
# Fix: block tenant-conn-bundle's deletion with a finalizer until
# tenant-sql-role's Object has actually been deleted (DROP ROLE done), then
# replayDeletion re-triggers it — so {connSecretName} only disappears after
# provider-sql no longer needs it.
_cluster_usage_conn = {
    apiVersion = "protection.crossplane.io/v1beta1"
    kind = "ClusterUsage"
    metadata = {
        name = short + "-conn-role-usage"
        annotations = {
            "crossplane.io/composition-resource-name" = "tenant-conn-role-usage"
        }
    }
    spec = {
        of = {
            apiVersion = "kubernetes.crossplane.io/v1alpha2"
            kind = "Object"
            resourceRef = {name = short + "-conn-bundle"}
        }
        by = {
            apiVersion = "kubernetes.crossplane.io/v1alpha2"
            kind = "Object"
            resourceRef = {name = short + "-sql-role"}
        }
        reason = "Block deletion of the connection-creds Secret until DROP ROLE has completed — provider-sql's Observe() reads passwordSecretRef even during Role deletion and deadlocks if the Secret is already gone."
        replayDeletion = True
    }
}

# ── ESO PushSecret: push connection bundle to Vault ────────────────
# Vault path: tenant/{owner}/{dbName}/connection-creds
# Pushes the WHOLE {connSecretName} secret (username, password, endpoint,
# port, database, connectionString — all built via _conn_bundle's template
# above) as a single write per reconcile (data[] entry has no
# secretKey/property) — listing each key individually would make ESO's Vault
# provider do one read-merge-write PER key, creating one KV2 version per key
# on every refresh instead of one per actual change.
#
# refreshInterval: "0" — under CreatedOnce (esoRefreshPolicy above),
# {connSecretName}'s password never changes after creation, so there's
# nothing to re-push periodically; ESO still pushes once on creation and
# again on any spec change.
#
# deletionPolicy follows databaseReclaimPolicy: Crossplane deletes all
# composed resources in parallel on XR deletion, so a PushSecret with
# deletionPolicy: Delete removes the Vault entry immediately — even if
# databaseReclaimPolicy: retain keeps the Database/Role alive (stuck on
# DROP ROLE's 2BP01 against the retained database). That would orphan a
# live database+role with no recorded credentials in Vault. So: "delete"
# -> Delete (Vault entry torn down alongside the dropped database/role),
# "retain" -> None (Vault keeps the creds for the retained database/role).
_pushDeletionPolicy = "Delete" if databaseReclaimPolicy == "delete" else "None"
_push_secret = {
    apiVersion = "kubernetes.crossplane.io/v1alpha2"
    kind = "Object"
    metadata = {
        name = short + "-push-secret"
        annotations = {
            "crossplane.io/composition-resource-name" = "tenant-push-secret"
        }
    }
    spec = {
        providerConfigRef = {name = "default"}
        forProvider = {
            manifest = {
                apiVersion = "external-secrets.io/v1alpha1"
                kind = "PushSecret"
                metadata = {name = roleName + "-push", namespace = clusterNs}
                spec = {
                    refreshInterval = "0"
                    deletionPolicy = _pushDeletionPolicy
                    secretStoreRefs = [{name = vaultStore, kind = "ClusterSecretStore"}]
                    selector = {
                        secret = {name = connSecretName}
                    }
                    data = [{
                        match = {
                            remoteRef = {remoteKey = vaultPath}
                        }
                    }]
                }
            }
        }
    }
}

# ── Final resource list ────────────────────────────────────────────
items = [
    _pwd_gen
    _conn_bundle
    _sql_role
    _cnpg_database
    _push_secret
] + ([_cluster_usage, _cluster_usage_conn] if databaseReclaimPolicy == "delete" else [])
