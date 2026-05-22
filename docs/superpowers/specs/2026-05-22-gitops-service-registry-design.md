# GitOps Service Registry — Design Spec

- **Date:** 2026-05-22
- **Status:** Approved (pending spec review)
- **Topic:** A single curated registry file that bootstraps additional services into the k3s cluster from remote public repos, via Argo CD `ApplicationSet`.

---

## 1. Context & Problem

The `labops` repo runs Argo CD as its CD layer. Today `argo/install` deploys Argo CD
and then applies `argo/app.index.yaml` — an app-of-apps `Application` that
**blanket-syncs the in-repo `apps/` directory**. Every child `Application` lives in the
`labops` monorepo and points at a *same-repo* path.

Two limitations follow:

- **Monorepo-bound.** Deploying anything means committing its manifests *into* `labops`.
  There is no way to "point at a remote repo and have it deploy."
- **Auto-loaded, uncurated.** `app.index.yaml` syncs *everything* under `apps/`, including
  apps that are now legacy.

The goal: a **single, curated registry** — one file listing services to deploy, each
pointing at a remote public repo or Helm chart — that programmatically generates the Argo
`Application`s. Adding a service becomes one list entry. Nothing deploys unless it is
explicitly listed.

Separately, an audit of the existing `argo/` install scripts — which this work runs as
the Argo CD install precursor — found correctness bugs and staleness (§4.4). Remediating
them is folded in, so the precursor is sound.

This is a single, cohesive capability — one spec, one plan.

---

## 2. Goals & Non-Goals

### Goals
- A single registry file, `argo/services.yaml` — a top-level YAML list; each entry is one service.
- Each entry generates exactly one Argo `Application`, synced to the cluster.
- Support **both** source types: `git` (raw manifests / Kustomize from a Git repo) and
  `helm` (a chart from a Helm repository).
- Add / change / remove a service = edit one list entry and commit — no other file touched.
- **Curated:** only services explicitly listed deploy. Nothing auto-loads.
- Use the modern Argo path (`ApplicationSet`), keeping the already-installed Argo CD.
- Correct and modernise the `argo/` install scripts (the install precursor) — fixing the
  audited bugs, anti-pattern, and hygiene issues.

### Non-Goals
- **Private repos / credential management** — all sources are public (no in-cluster repo secrets).
- **Multi-cluster** — single cluster (the NUC).
- **Hard ordering / a dependency graph** — ordering is eventual-convergence only (§5).
- **Migrating the existing `apps/` demo catalogue into the registry** — a separate follow-up.
- **Cleaning up legacy `apps/` content** — a separate follow-up.
- **Flux CD** — evaluated during brainstorming; recorded here as a future side-track (§7),
  not built.

---

## 3. Decisions

Settled during brainstorming:

| # | Decision | Choice |
|---|----------|--------|
| 1 | Tooling | Keep Argo CD; use `ApplicationSet` (the modern fan-out — supersedes app-of-apps) |
| 2 | Declaration UX | A single registry file, `argo/services.yaml`, a top-level YAML list |
| 3 | Generator | `ApplicationSet` **Git file generator** — a single list file yields one Application per element |
| 4 | Source types | `git` and `helm`, handled by one `ApplicationSet` with a `goTemplate` conditional source |
| 5 | Repo access | All public — no credentials, no secret management |
| 6 | Cluster scope | Single cluster (the NUC) — no multi-cluster generators |
| 7 | Existing catalogue | The registry is the **single** mechanism; the `app.index.yaml` auto-loader is **retired**; `apps/` stays as inert repo content; nothing auto-loads |
| 8 | Ordering | Eventual convergence via per-Application `syncPolicy.retry`; no ordering field in the schema |
| 9 | Argo CD on the NUC | Installed as an implementation precursor (existing `argo/` scripts) so the registry can be acceptance-tested live end-to-end |
| 10 | `argo/` scripts | All audited bugs + the anti-pattern + hygiene issues remediated in this work (§4.4) |
| 11 | Argo CD version | Sourced from the `stable` branch (unpinned) — consistent with the repo's track-latest stance |
| 12 | `argo/` module consistency | All 5 scripts gain the standard module header; `cli-install` adopts the `run` resolver — parity with the k3s modules (§4.4) |

---

## 4. Architecture & Components

```
argo/services.yaml ──(Git file generator)──▶ ApplicationSet ──generates──▶ N × Application ──Argo CD syncs──▶ cluster
   (the registry list,                        (write-once,                  (one per entry)
    user-facing)                               goTemplate)
```

The Argo CD **applicationset-controller** reads `argo/services.yaml`, renders the
`Application` template once per list element, and reconciles the resulting `Application`s
(create / update / prune). The **application-controller** then syncs each `Application`.
Both controllers already ship in the Argo CD `stable` manifests `argo/install` applies —
**this spec installs no new cluster components**, only repo files.

### Change set (all in `labops/argo/`)

| File | Change | Role |
|------|--------|------|
| `argo/services.yaml` | **new** | the registry — the YAML list you edit to add/remove a service |
| `argo/services.appset.yaml` | **new** | the `ApplicationSet` — write-once; generates Applications from the registry |
| `argo/install` | **edit** | apply `services.appset.yaml`; make namespace creation idempotent (§4.3) |
| `argo/app.index.yaml` | **remove** | the retired auto-loader |
| `argo/set-service` | **edit** | add the LoadBalancer *alongside* `argocd-server`, not delete it (§4.4) |
| `argo/cli-install` | **edit** | drop the `/dev/tty` redirect + dead var; CLI → `/usr/local/bin` (§4.4) |
| `argo/set-password` | **edit** | add `admin.passwordMtime` (§4.4) |
| `argo/remove` | **edit** | delete the `services` ApplicationSet, not the retired `index` app (§4.4) |

`argo/runonce.sh` is unaffected — it calls `argo/install`, so it picks up the change with
no edit. The `apps/` directory and its now-inert `apps/app.*.yaml` child manifests are
left in place (cleanup is a separate follow-up, per §2).

### 4.1 `argo/services.yaml` — the registry

A top-level YAML list. Each element is one service:

```yaml
# Each entry deploys one service. Add an entry, commit — it deploys.
- name: podinfo
  type: git
  repoURL: https://github.com/stefanprodan/podinfo
  path: kustomize
  revision: master
  namespace: podinfo

- name: ingress-nginx
  type: helm
  repoURL: https://kubernetes.github.io/ingress-nginx
  chart: ingress-nginx
  revision: 4.11.3
  namespace: ingress-nginx
  values:
    controller:
      replicaCount: 1
```

| Field | Required | Applies to | Meaning |
|-------|----------|-----------|---------|
| `name` | yes | both | Argo `Application` name — must be unique within the registry |
| `type` | yes | both | `git` or `helm` |
| `repoURL` | yes | both | Git repo URL (`git`) or Helm repository URL (`helm`) |
| `revision` | yes | both | Git ref — branch / tag / SHA (`git`) — or chart version (`helm`) |
| `namespace` | yes | both | destination namespace (auto-created) |
| `path` | yes | `git` | directory within the repo; Argo auto-detects plain manifests / Kustomize / an in-repo chart |
| `chart` | yes | `helm` | chart name within the Helm repository |
| `values` | no | `helm` | inline Helm values (a YAML map) |

The schema is deliberately minimal — no ordering / `syncWave` field (see §5).

### 4.2 `argo/services.appset.yaml` — the ApplicationSet

A single `ApplicationSet` (`metadata.name: services`, namespace `argocd`), write-once:

- **Generator:** Git file generator — `repoURL` the `labops` repo, `revision: HEAD`,
  `files: [{ path: argo/services.yaml }]`. Because `services.yaml` is a top-level list,
  the generator yields one parameter set per element.
- **`goTemplate: true` + `templatePatch`** — `goTemplate` substitutes `{{ .field }}` into
  the template's string values. The git-vs-helm *structural* choice (`source.path` vs
  `source.chart`/`helm`) cannot be a bare conditional in the manifest, so it lives in
  `spec.templatePatch` — a Go-templated string block that renders a strategic-merge patch
  onto the template: `git` patches in `source.path`; `helm` patches in `source.chart`
  (plus `source.helm.valuesObject` when `values` is set, injected as JSON via `toJson`).
- **Template `syncPolicy`** (every generated `Application`): `automated` with `selfHeal: true`
  and `prune: true`; `syncOptions: [CreateNamespace=true]`; and a bounded `retry` (`limit: 5`,
  exponential `backoff` capped at ~10m) — the retry is what makes eventual convergence work (§5).

The manifest is valid YAML — the `{{ }}` conditionals sit inside the `templatePatch: |`
string; the template *rendering* is validated against the live Argo CD in the plan:

```yaml
spec:
  goTemplate: true
  generators:
    - git: { repoURL: <labops repo>, revision: HEAD, files: [{ path: argo/services.yaml }] }
  template:
    metadata: { name: '{{ .name }}' }
    spec:
      project: default
      destination: { server: https://kubernetes.default.svc, namespace: '{{ .namespace }}' }
      source: { repoURL: '{{ .repoURL }}', targetRevision: '{{ .revision }}' }
      syncPolicy:
        automated: { selfHeal: true, prune: true }
        syncOptions: [ CreateNamespace=true ]
        retry: { limit: 5, backoff: { duration: 30s, factor: 2, maxDuration: 10m } }
  templatePatch: |
    spec:
      source:
        {{- if eq .type "helm" }}
        chart: {{ .chart | quote }}
        {{- if .values }}
        helm:
          valuesObject: {{ .values | toJson }}
        {{- end }}
        {{- else }}
        path: {{ .path | quote }}
        {{- end }}
```

### 4.3 `argo/install` — edited

Two changes: (1) apply `argo/services.appset.yaml` in place of `argo/app.index.yaml` as
the final step; (2) make namespace creation idempotent —
`kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -` — so
re-runs don't error. Argo CD continues to install from the `stable` branch (decision #11).

### 4.4 `argo/` install-script remediation

The audit of the scripts this work runs as the install precursor found:

- **`argo/set-service`** — currently `kubectl delete`s the `argocd-server` Service before
  applying the `vip-argocd-server` LoadBalancer. The delete is needless and mildly risky
  (the vip is a *separate* service). Fix: apply the LoadBalancer *alongside*; leave
  `argocd-server` intact; drop the dead commented-out patch block. Idempotent.
- **`argo/cli-install`** — `2>/dev/tty` on the healthcheck calls breaks in non-interactive
  runs (no controlling terminal). Fix: remove the redirect — stderr flows to the script's
  own stderr. Remove the dead `ARGOCD_THUMBPRINT` capture (keep the `net-ssl` call, which
  doubles as a readiness wait). Install the CLI to `/usr/local/bin/argocd` (was `/usr/bin`).
- **`argo/set-password`** — patches only `admin.password`. Fix: also set
  `admin.passwordMtime` (an RFC3339 timestamp) — Argo's documented password reset patches
  both; the timestamp registers the change and invalidates stale tokens. Correct the stale
  `## from stdin` comment (the value is `$1`); quote variables.
- **`argo/remove`** — deletes the retired `index` app-of-apps. Fix: delete the `services`
  `ApplicationSet` instead (its deletion cascades to the generated Applications); keep the
  stuck-app finalizer-clear loop as a safety net; use `--ignore-not-found` for idempotency.

**Module consistency** (parity with the k3s modules): every script above (`install`,
`set-service`, `cli-install`, `set-password`, `remove`) also gains the standard
`## module / purpose / inputs / needs` header. `cli-install` additionally adopts the
inlined `run` module resolver for its `healthcheck/k8s-external-ip` and
`healthcheck/net-ssl` calls — both healthchecks accept positional args, so the bare
`curl … | bash` pattern is replaced by `run healthcheck/… <args>`. The other four scripts
call no sibling scripts, so they take only the header. There are no inline wait-loops in
`argo/` to dedupe — `cli-install` already uses the healthcheck modules.

---

## 5. Data Flow, Ordering & Error Handling

### Data flow (steady state)
1. You edit `argo/services.yaml`, commit + push to `labops`.
2. The applicationset-controller polls `labops` (≈3 min default; instant if a webhook is
   configured), reads the list.
3. Per element → renders the `Application` template (`goTemplate` branches on `type`).
4. It reconciles: new entry → new `Application`; changed entry → updated; **removed entry
   → its `Application` is pruned** — the service is deleted. The registry is the source of
   truth, so deleting a line deletes the deployment.
5. The application-controller syncs each `Application`; resources land in the target namespace.

### Ordering
Each generated `Application` is independent — there is no app-of-apps parent, so Argo's
`sync-wave` does not order across them, and there is no hard ordering primitive. The design's
answer is **eventual convergence**: the template sets `syncPolicy.retry` with capped
backoff, so if a service races ahead of a dependency, its sync fails, backs off, and
self-heal re-attempts until the dependency is up. For a single-node lab platform this is
adequate. It is **not** hard ordering — that is the one area Flux's `dependsOn` is cleaner
(§7). The schema therefore has no `syncWave` field, which would be misleading.

### Error handling
- **Bad entry** (typo'd `repoURL`, wrong `chart`/`revision`): that one `Application` shows
  Degraded/Failed in the Argo UI and `kubectl get applications -n argocd`. **Every other
  service is unaffected** — Applications are independent. Fix the entry, commit, it recovers.
- **Malformed `services.yaml`** (invalid YAML, or not a top-level list): the Git file
  generator fails to parse; the `ApplicationSet` status surfaces the error and **keeps the
  last good set of Applications** — running services are not torn down. A bad registry
  commit stalls changes; it does not break the cluster.
- **An upstream repo breaks** (a tag is deleted, a chart version pulled): only that
  `Application`'s sync fails; isolated and visible in the UI.
- **Deleting the `ApplicationSet`** cascades to the generated `Application`s by default —
  not a normal-operation action, noted for awareness.

---

## 6. Verification & Testing

GitOps configuration — verification is behavioural, not unit-tested:

- **Argo CD prerequisite:** the NUC does not yet run Argo CD — `k3s/up` stops at k3s +
  MetalLB + storage + metrics. The implementation installs Argo CD first, via the existing
  `argo/` scripts (`install` → `set-service` → `cli-install` → `set-password`), so the
  acceptance below can run end-to-end.
- Every edited `argo/` script (`install`, `set-service`, `cli-install`, `set-password`,
  `remove`) must be `shellcheck`-clean.
- The `ApplicationSet` and `services.yaml` are YAML — validate with `kubectl apply --dry-run`.
- **Acceptance:** with Argo CD running, apply the `ApplicationSet`, then:
  - add a known-good `git` entry (e.g. `podinfo`) → confirm the `Application` is generated
    (`kubectl get applications -n argocd`), syncs `Healthy`, and the workload runs in its namespace;
  - add a `helm` entry (a small public chart) → exercises the `goTemplate` helm branch;
  - remove an entry → confirm the `Application` and its resources are pruned.
- The Argo CD UI (host IP `:8472`) shows every generated Application — also the demo-time view.

---

## 7. Risks & Notes

- **Ordering is eventual-convergence, not hard ordering** (§5) — adequate for a single-node
  lab; a genuine hard dependency is a known gap (where Flux's `dependsOn` would be cleaner).
- **Poll latency** — the Git file generator polls ≈3 min by default; services do not deploy
  instantly. A Git webhook to the applicationset-controller removes the lag — optional, not in scope.
- **Mutable revisions** — a `git` entry tracking a branch (`main`/`master`) follows the
  branch tip; pinning `revision` to a tag or SHA is more reproducible. The schema permits
  either; pinning is recommended guidance, not enforced.
- **Removing an entry deletes the service** — by design (registry = source of truth), but
  worth internalising: a one-line deletion prunes a running deployment.
- **`flux/` evaluation side-track** — Flux CD is a viable modern alternative (continuous
  reconciliation; `GitRepository`/`HelmRepository` sources; `Kustomization`/`HelmRelease`
  reconcilers; `dependsOn` ordering). It was set aside because it has no native single-file
  fan-out generator — the exact model chosen here — and would mean replacing Argo CD and its
  UI. A future `flux/` module could trial it **on an isolated cluster** (`kind/`, or a
  dedicated NUC rebuild); Flux and Argo must not both actuate the same cluster. Out of scope
  for this spec.
