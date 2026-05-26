# labops/kyverno — admission policies (OPTIONAL, not in default k3s/up)

Kyverno install + a sample ClusterPolicy. **Not part of the default
substrate bootstrap** — `k3s/up` does NOT include these modules.

## Why not default?

Investigated 2026-05-26 (see
`apnex/kate/docs/research/platform-migration/03-phase-a-kyverno-investigation.md`)
and found that the MetalLB autoAssign mechanism already provides
substrate-default IP-pool selection. Component manifests ship with
NO pool annotation and MetalLB picks the first matching `autoAssign:
true` pool. The substrate-level admission-mutation pattern was solving
a non-problem.

Kyverno is kept here as **available infrastructure** for future use
cases where admission-time mutation/validation IS needed, such as:

- multi-substrate environments where the default-pool name varies
  between clusters (dev-pool vs prod-pool vs host-pool)
- enforcing namespace-level conventions (resource limits, labels)
- validating that PVCs use a specific StorageClass for backups
- blocking dangerous patterns (privileged pods, hostNetwork, etc.)
- generating sidecars or default network policies

## Usage (when you need it)

```bash
# install (idempotent)
bash kyverno/install

# apply policies in this directory
bash kyverno/prepare

# remove everything
bash kyverno/remove
```

The scripts follow the labops module pattern (resolver, healthchecks,
env-pinnable versions) — see `metallb/install` for the canonical
pattern they mirror.

## Files

- `install` — `kubectl apply` the upstream Kyverno install.yaml
  (server-side apply, version-pinnable via `KYVERNO_VERSION`)
- `prepare` — waits for the admission controller + ClusterPolicy CRD,
  applies all policy YAMLs in this directory
- `remove` — uninstall (deletes ClusterPolicies first, then the
  Kyverno install)
- `policy-default-metallb-pool.yaml` — the sample ClusterPolicy from
  the Phase-A investigation. **Kept for reference / future adaptation.**
  It mutates LoadBalancer Services in non-substrate namespaces to add
  `metallb.io/ip-allocated-from-pool: host-pool` if absent. Use only
  if a future substrate has multiple autoAssign pools where the wrong
  one might win.

## Phase A finding in one sentence

> The existing component manifests are already substrate-portable;
> the autoAssign mechanism in MetalLB IS the substrate-decoration
> layer; adding Kyverno on top would be redundant operational surface.
