# Monitoring Approach (Honcho + Hermes + Cluster)

Status: **design doc, not yet implemented.** Captured here so the rollout
is a mechanical exercise when we decide to activate it.

## Goal

End-to-end observability for honcho, hermes, and the k3s cluster
itself, delivered the same way the rest of labops is delivered:
GitOps-native via ArgoCD, source of truth in this repo, zero
snowflakes, no UI-click configuration that isn't reflected in Git.

Secondary goal: a usable "control panel" for Honcho via a Grafana
Postgres datasource + SQL panels, since upstream Honcho ships no
admin UI today. This lets us browse peers, sessions, conclusions,
and working representations without writing a custom frontend.

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│  apnex/labops  (Git = source of truth)                      │
│  └── apps/monitoring/                                       │
│      ├── kube-prometheus-stack/   (Argo App, Helm)          │
│      ├── exporters/               (Argo App, manifests)     │
│      └── dashboards/              (Argo App, ConfigMaps)    │
└───────────────┬─────────────────────────────────────────────┘
                │ ArgoCD sync
                ▼
┌─────────────────────────────────────────────────────────────┐
│  ns: monitoring                                             │
│                                                             │
│   prometheus ──scrapes──► postgres-exporter ──► postgres-0  │
│       │                   redis-exporter    ──► redis       │
│       │                   honcho /metrics   ──► honcho api  │
│       │                   kube-state-metrics, node-exporter │
│       ▼                                                     │
│   grafana ◄──reads── prometheus                             │
│       │       └──── postgres datasource (ad-hoc SQL panels) │
│       │                                                     │
│       └── Service type=LoadBalancer (MetalLB)               │
│           Separate VIP (not shared with .250)               │
└─────────────────────────────────────────────────────────────┘
```

## Components and rationale

- **kube-prometheus-stack** (Helm chart, version-pinned in
  `Application.yaml`). Bundles Prometheus + Grafana + Alertmanager
  + node-exporter + kube-state-metrics + a large catalogue of
  pre-built k8s dashboards. Avoids assembling the stack by hand.
- **postgres-exporter** with a custom-queries ConfigMap. Honcho's
  truth lives in Postgres; the exporter surfaces both stock
  `pg_stat_*` metrics and Honcho-specific gauges (peer counts,
  session activity, conclusions per peer, deriver lag).
- **redis-exporter**. Deriver job queue lives in Redis. We want
  `redis_list_length` on the queue key, hit/miss ratios, memory.
- **honcho /metrics**. If the FastAPI app exposes
  `prometheus-fastapi-instrumentator` (TBD — recon needed), free
  request-latency / error-rate panels. If not, postgres-exporter
  custom queries fill the gap and we file an upstream issue.
- **Grafana sidecar pattern** (kiwigrid/k8s-sidecar, ships with
  the chart). Watches the cluster for labeled ConfigMaps and
  drops them into Grafana's provisioning directory in real time.
  Same pattern handles dashboards, datasources, and alert rules.

## Repo layout (proposed)

```
apps/monitoring/
├── namespace.yaml                          # ns: monitoring + labels
├── kube-prometheus-stack/
│   ├── Application.yaml                    # Argo App → upstream Helm
│   └── values.yaml                         # retention, storage, VIP, auth
├── exporters/
│   ├── Application.yaml                    # Argo App → ./manifests
│   └── manifests/
│       ├── postgres-exporter.yaml          # Deployment + Service + Secret-ref
│       ├── postgres-exporter-queries.yaml  # ConfigMap: honcho_* metrics
│       └── redis-exporter.yaml
└── dashboards/
    ├── Application.yaml                    # Argo App → ./manifests
    ├── manifests/
    │   ├── honcho-overview.yaml            # ConfigMap, label grafana_dashboard=1
    │   ├── honcho-peers.yaml
    │   ├── deriver-health.yaml
    │   └── infra-overview.yaml
    ├── scripts/
    │   └── clean-export.sh                 # UI export → ConfigMap pipeline
    └── README.md                           # "how to add/edit a dashboard"
```

## Dashboards-as-code — plain JSON v1

**Mechanism.** ConfigMaps in the `monitoring` namespace labeled
`grafana_dashboard: "1"` are picked up by the Grafana sidecar
container, written to Grafana's filesystem, and auto-loaded. No
UI clicks, no manual import, no Grafana DB seeding. Same applies
to datasources (`grafana_datasource: "1"`) and alert rules
(`grafana_alert: "1"`).

**Author loop.**

```
1. Open Grafana on its LAN VIP.
2. Build/edit the dashboard interactively in the UI.
3. Share → Export → Save to file → ~/Downloads/<name>.json.
4. ./apps/monitoring/dashboards/scripts/clean-export.sh \
       ~/Downloads/<name>.json > \
       apps/monitoring/dashboards/manifests/<name>.yaml
5. git add . && git commit && git push.
6. ArgoCD syncs the ConfigMap; sidecar reloads Grafana (~5 s after sync).
```

**`clean-export.sh` responsibilities.**

- Strip `__inputs`, `__elements`, `__requires` (per-export
  metadata that bloats diffs).
- Pin `version: 1` (Grafana increments on every UI save —
  pinning kills version churn in Git).
- Template datasource UIDs to `${DS_PROMETHEUS}` /
  `${DS_HONCHO_POSTGRES}` so they resolve against whatever the
  cluster has provisioned, not the cluster that exported the JSON.
- Wrap the JSON in the ConfigMap YAML envelope and write to
  `apps/monitoring/dashboards/manifests/`.

**Constraints.**

- k8s ConfigMap size cap is 1 MiB. A typical dashboard is
  10-50 KiB; comfortable headroom. One ConfigMap per dashboard
  keeps `git diff` readable.
- If a single dashboard ever exceeds 1 MiB (100+ panels), sidecar
  also reads from Secrets or external URLs as an escape hatch.

## Graduation path — jsonnet + grafonnet

We deliberately defer jsonnet for v1 (4-5 dashboards, single
environment, no cross-team panel reuse — repetition isn't yet
painful). Document so the path is obvious when it earns its place.

**Revisit when any of these become true.**

- A second environment appears (dev/staging cluster) and the same
  dashboards need per-env templating.
- A "per-service" dashboard pattern emerges (one dashboard per
  microservice, generated from a service list).
- Adopting `kube-prometheus` (the jsonnet-native cousin of
  `kube-prometheus-stack`) for its mixin libraries.
- Sharing panel libraries across teams/repos — `import
  'honcho-panels.libsonnet'` from multiple dashboards.

**Toolchain (when adopted).**

- `jsonnet` (Go binary) — compiler.
- `jsonnet-bundler` (`jb`) — package manager.
- `grafonnet` — Grafana Labs' typed-constructor library wrapping
  the dashboard schema. Installed via `jb install
  github.com/grafana/grafonnet/gen/grafonnet-latest`.
- `jsonnetfmt`, `jsonnet-lint` — optional but recommended.

**Build pattern.** Build locally, commit the generated YAML. Argo
stays jsonnet-unaware (no CMP plugin). Pre-commit hook + CI check
prevent forgetting the build step. Generated YAML is what gets
reviewed in PRs — readable, diffable.

**Migration cost.** Zero. ArgoCD doesn't care whether the
ConfigMap was hand-written or jsonnet-generated. Port dashboards
one at a time, extract reusable panels into a `honcho-panels.libsonnet`
library incrementally. No big-bang migration.

## Networking

- **MetalLB VIP.** Grafana gets its own VIP (e.g. `192.168.1.251`).
  Sharing `.250` with Honcho via `metallb.universe.tf/allow-shared-ip`
  is technically possible but couples lifecycles unnecessarily.
- **Pool expansion required first.** Current pool is a single
  `/32` (`192.168.1.250/32`). All four existing LoadBalancer
  services already share that one IP. Before monitoring goes live,
  expand the pool (e.g. `192.168.1.250-192.168.1.254`) in
  `apps/metallb/` and let Argo sync.
- **No internet exposure (v1).** LAN-only is good enough.
  Future: oauth2-proxy + Tailscale in front if exposed.

## Storage

- **Prometheus PVC.** 20 GiB on `local-path` (default SC).
  15-day retention. Tune retention up if disk allows.
- **Grafana PVC.** 2 GiB. Holds users/orgs/plugins. State is
  disposable — dashboards live in Git, datasources live in Git,
  Grafana pod is cattle.

## Auth (v1)

- Grafana admin password from a k8s Secret. Plain Secret to start;
  graduate to sealed-secrets or external-secrets when labops
  adopts one of those patterns repo-wide.
- Postgres read-only role (`grafana_ro`) created via a migration
  manifest; credentials in a separate Secret referenced by both
  the Grafana datasource ConfigMap and a `secretGenerator`.

## Honcho-specific custom metrics

Defined in `apps/monitoring/exporters/manifests/postgres-exporter-queries.yaml`
as a ConfigMap consumed by postgres-exporter via
`--extend.query-path=`.

```yaml
honcho_peers_total:
  query: "SELECT count(*) FROM peers"
  metrics: [{count: {usage: GAUGE}}]

honcho_sessions_active_24h:
  query: |
    SELECT count(*) FROM sessions
    WHERE updated_at > now() - interval '24 hours'
  metrics: [{count: {usage: GAUGE}}]

honcho_messages_total:
  query: "SELECT count(*) FROM messages"
  metrics: [{count: {usage: COUNTER}}]

honcho_conclusions_by_peer:
  query: |
    SELECT peer_id, count(*) AS count
    FROM conclusions GROUP BY peer_id
  metrics:
    - peer_id: {usage: LABEL}
    - count:   {usage: GAUGE}

honcho_deriver_lag_seconds:
  # Time between most-recent message insert and most-recent
  # conclusion insert. The single most important signal —
  # if this grows, dialectic is falling behind.
  query: |
    SELECT EXTRACT(EPOCH FROM (
      (SELECT max(created_at) FROM messages) -
      (SELECT max(created_at) FROM conclusions)
    )) AS lag_seconds
  metrics: [{lag_seconds: {usage: GAUGE}}]
```

Deriver queue depth comes from redis-exporter via `LLEN` on the
queue key (key name TBD during recon).

## Planned dashboards

1. **Honcho Overview** — peers, sessions/24h, messages/24h,
   conclusions/24h, deriver queue depth, deriver lag, API
   p50/p95/p99 latency, error rate.
2. **Peer Inspector** — Postgres datasource. Dropdown selector
   for peer. Shows recent conclusions, working_representation
   freshness, session count, message volume.
3. **Deriver Health** — queue depth over time, jobs/min
   throughput, average job duration, failed jobs, dialectic
   depth=3 reconciliation timings.
4. **Infra Overview** — node CPU/mem/disk, postgres connections
   + slow queries, redis memory and ops/sec.
5. **Hermes** (bonus, same stack) — pod restarts, CPU/mem,
   message rate if `/metrics` is exposed.

## Rollout plan (when activated)

Apply standard discipline: recon → blast-radius → dry-run → wait
per stage.

1. **Recon (5 min).** Confirm MetalLB pool expanded, `local-path`
   still default SC, Honcho `/metrics` reachable (via
   `kubectl port-forward` or ephemeral curl pod), Postgres
   credentials available as a Secret consumable by exporter +
   Grafana, chart version pinned.
2. **Branch.** Scaffold `apps/monitoring/` with all four Argo
   Applications. `syncPolicy: manual` initially.
3. **Dry-run.** `argocd app diff <app>` for each before flipping
   to automated sync.
4. **Apply in order.** namespace → kube-prometheus-stack
   (wait for Healthy) → exporters → dashboards. ~10 min.
5. **Verify.** Hit Grafana VIP, log in, confirm Honcho Overview
   renders with non-zero values.
6. **Auto-sync on** once green.

**Blast radius.** Zero on Honcho and Hermes. Monitoring is pure
read-side. Worst case: exporter pods crash-loop in their own
namespace; nothing in `honcho` or `hermes` ns is touched.

**Estimated effort.** ~90 min if Honcho `/metrics` is already
exposed. Add ~30 min if custom postgres-exporter queries need
extra debugging.

## Open recon items (blockers when we go live)

- **MetalLB pool expansion.** Currently `192.168.1.250/32` only.
  All four existing LoadBalancer services share that one IP.
  Expand the pool (e.g. `192.168.1.250-192.168.1.254`) in
  `apps/metallb/` before standing up monitoring's separate VIP.
- **Honcho /metrics verification.** Honcho image is minimal —
  no `wget` / `curl` in the container. Verify endpoint via
  `kubectl port-forward -n honcho svc/honcho 8000:8000` then
  `curl localhost:8000/metrics`, or use an ephemeral pod
  (`kubectl run -it --rm curl --image=curlimages/curl`).
- **Postgres read-only role.** Create `grafana_ro` role + Secret
  for the Grafana Postgres datasource. Either a migration manifest
  in the Honcho ArgoCD app, or a one-shot Job in
  `apps/monitoring/`.
- **kube-prometheus-stack chart version.** Pin a specific chart
  version in `Application.yaml`. Bump deliberately.
- **Deriver queue key name.** Confirm the Redis list key used by
  the deriver so the redis-exporter `LLEN` query targets it
  correctly.

## Non-goals (v1)

- **No Alertmanager routing.** Dashboards first, alerts second.
  When alerts come online, route to Discord webhook via
  `discord-alertmanager-webhook` or similar.
- **No log aggregation (Loki).** Separate effort if/when needed.
- **No distributed tracing (Tempo).** Separate effort.
- **No multi-cluster.** Single k3s on obpc only.
- **No public exposure.** LAN-only. If exposed later, gate behind
  oauth2-proxy + Tailscale.
