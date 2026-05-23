# Hermes Agent Deployment — Design Spec

- **Date:** 2026-05-22
- **Status:** Approved (pending spec review)
- **Topic:** GitOps-deployed standalone Hermes agent on the NUC k3s cluster.
- **Related:** `docs/superpowers/hermes-platform-roadmap.md` (§9 — Phase A research).

---

## 1. Context & Problem

The NUC k3s cluster runs Argo CD and the `services` GitOps registry (see
`2026-05-22-gitops-service-registry-design.md`). The goal is a **persistent Hermes agent**
(`NousResearch/hermes-agent`) running on that cluster, fully GitOps-managed.

Phase A research (roadmap §9) established that **Hermes is a self-contained agent
application, not a kagent agent** — it deploys as an ordinary Kubernetes workload. kagent /
kgateway / agentgateway are parked as a separate effort. This spec covers the standalone
Hermes deployment only. It is a single, cohesive capability — one spec, one plan.

---

## 2. Goals & Non-Goals

### Goals
- Deploy Hermes as a standalone, stateful Kubernetes workload on the NUC k3s cluster.
- GitOps-managed: Hermes's manifests live in a dedicated repo and deploy via the existing
  Argo CD `services` registry.
- Reachable two ways: the OpenAI-compatible **API** (`:8642`) and the **web dashboard** (`:9119`).
- Hermes uses the remote OpenAI-compatible **LiteLLM router** for inference, default model
  `smart-coder`.
- Persistent: skills, sessions, and memory survive pod restarts.
- **The `apnex/hermes` repo is a generic, reusable public deployment template.** No
  operator-specific values are committed — all per-deployment specifics (LiteLLM base URL,
  model, key, API server key) live in the operator's Secret; cluster-specific exposure
  (e.g. MetalLB LoadBalancer) lives as an overlay in the operator's own GitOps repo.

### Non-Goals
- **Messaging-platform gateways** (Telegram / Discord / Slack / …) — not deployed.
- **kagent / kgateway / agentgateway** integration — parked (separate effort; roadmap §9).
- **Multi-user, multi-replica, HA** — single-instance personal agent.
- **TLS** — plain HTTP on the LAN for v1.
- **In-git secret encryption** (Sealed Secrets / SOPS) — a manually-applied, env-sourced
  Secret is used instead.

---

## 3. Decisions

| # | Decision | Choice |
|---|----------|--------|
| 1 | Deployment model | Standalone Kubernetes workload (Phase A: Hermes is not a kagent agent) |
| 2 | Repo | New public repo `github.com/apnex/hermes`; plain Kubernetes manifests |
| 3 | GitOps wiring | One entry in `labops/argo/services.yaml`; the existing `services` ApplicationSet deploys it |
| 4 | Namespace | `hermes` (auto-created by Argo CD `CreateNamespace=true`) |
| 5 | Replicas / state | `replicas: 1`; stateful; RWO `local-path` PVC at `/opt/data` |
| 6 | Image | Pinned — `nousresearch/hermes-agent:v2026.5.16` |
| 7 | Interfaces | API `:8642` + dashboard `:9119`; no messaging gateways |
| 8 | `config.yaml` | Seeded via ConfigMap + init container (seed-if-absent); Hermes owns it after first boot |
| 9 | Model | Operator-supplied via `LITELLM_MODEL` in the Secret (per their router's naming); this deployment uses `smart-coder` (Claude Opus 4.7) |
| 10 | Secrets | Manually-applied `hermes-secrets` Secret with **four** values — `LITELLM_BASE_URL`, `LITELLM_MODEL`, `LITELLM_API_KEY`, `API_SERVER_KEY` — created out-of-band by the `set-secret` script from env vars; not in git, not Argo-managed |
| 11 | Exposure | Hermes repo ships a portable `ClusterIP` Service; a separate `vip-hermes` MetalLB LoadBalancer overlay (`allow-shared-ip: host`, NUC IP `192.168.1.250`) lives in `labops/hermes-vip/` and is registered as a second entry in `services.yaml` |
| 12 | TLS | Plain HTTP (LAN); the API is guarded by the `API_SERVER_KEY` bearer token |

---

## 4. Architecture & Components

```
apnex/hermes repo ──(services.yaml entry)──▶ Argo CD `services` ApplicationSet
                                                      │
                                                      ▼
                                          namespace `hermes`:
                                          Deployment + PVC + ConfigMap + Service
                                                      │  (Secret applied out-of-band)
                                                      ▼
                                  Hermes pod ──HTTPS──▶ remote LiteLLM router (smart-coder)
```

### 4.1 The `apnex/hermes` repo

A new **public** repo, plain Kubernetes manifests (one app, no overlays — Argo CD
auto-detects plain manifests). Layout:

```
apnex/hermes/
  README.md            # what it is, how to deploy, the set-secret step
  set-secret           # env-reading Secret creation script (run out-of-band)
  manifests/           # the directory Argo CD syncs
    pvc.yaml
    configmap.yaml
    deployment.yaml
    service.yaml
```

No `Namespace` manifest — Argo CD's `CreateNamespace=true` handles it. No `CLAUDE.md` —
this is a deployment-artifact repo, not an agent-development repo.

### 4.2 Registry entries (added to `labops/argo/services.yaml`)

Two entries — the Hermes deployment itself (in `apnex/hermes`), and the local MetalLB
LoadBalancer overlay (in `apnex/labops`):

```yaml
- name: hermes
  type: git
  repoURL: https://github.com/apnex/hermes
  gitPath: manifests
  revision: main
  namespace: hermes

- name: hermes-vip
  type: git
  repoURL: https://github.com/apnex/labops
  gitPath: hermes-vip
  revision: master
  namespace: hermes
```

### 4.3 Cluster objects (namespace `hermes`)

- **`Deployment` hermes** — `replicas: 1`; image `nousresearch/hermes-agent:v2026.5.16`;
  command `["hermes","gateway","run"]`. An **init container** (busybox) seeds `config.yaml`
  (§5.1). Liveness + readiness probes on `GET /health` (`:8642`). Resource requests/limits
  roughly cpu `500m`→`2`, memory `1Gi`→`4Gi` (tunable; exact values set in the plan).
- **`PVC` hermes-data** — `local-path`, 10Gi, RWO; mounted at `/opt/data` in both the init
  and main containers.
- **`ConfigMap` hermes-config** — holds the seed `config.yaml`.
- **`Secret` hermes-secrets** — the two keys; created out-of-band (§5.2), referenced by name.
- **`Service` hermes** — `ClusterIP`; the `vip-hermes` MetalLB LoadBalancer overlay lives in `labops/hermes-vip/` (§6).

---

## 5. Config & Secrets

### 5.1 `config.yaml` — templated, seeded, then Hermes-owned

The LiteLLM router's **base URL** and **default model name** are both operator-specific —
each adopter's router has a different URL and exposes different model IDs. To keep the
public repo generic, neither value lives in the repo; both come from the operator's
Secret. The ConfigMap holds a **template**; the init container substitutes both at first
boot. Hermes then reads and *mutates* `/opt/data/config.yaml` at runtime, so the file
lives on the PVC, not on a mounted ConfigMap.

**ConfigMap `hermes-config`** — holds `config.yaml.tpl` matching Hermes's real
`custom`-provider schema (verified against `/opt/hermes/cli-config.yaml.example` in the
image at implementation):

```yaml
model:
  provider: "custom"
  base_url: "@LITELLM_BASE_URL@"
  default: "@LITELLM_MODEL@"
  api_key: "@LITELLM_API_KEY@"
```

**Init container** (busybox) — mounts the ConfigMap at `/seed` and the PVC at `/opt/data`;
gets all three values (`LITELLM_BASE_URL`, `LITELLM_MODEL`, `LITELLM_API_KEY`) from the
Secret. It **always regenerates** `config.yaml` on every pod start — the Secret is the
source of truth for this gateway-only deployment, and no runtime `hermes config set` flow
is used:

```sh
sed -e "s|@LITELLM_BASE_URL@|${LITELLM_BASE_URL}|g" \
    -e "s|@LITELLM_MODEL@|${LITELLM_MODEL}|g" \
    -e "s#@LITELLM_API_KEY@#${LITELLM_API_KEY}#g" \
    /seed/config.yaml.tpl > /opt/data/config.yaml
```

(`#` is the sed delimiter for the API key — keys may contain `|` or `/`; `|` is safe for
URL and model.) Because regeneration is unconditional, updating the operator's Secret
values and bouncing the pod is the supported config-change flow. The literal API key
value lands on the PVC inside `/opt/data/config.yaml`; **the key is never in the public
git repo** — only the `@LITELLM_API_KEY@` placeholder is. The PVC's contents are local to
the node.

*Earlier draft used `key_env: LITELLM_API_KEY` and a seed-if-absent guard — Phase A
research mis-stated Hermes's schema; corrected during HE-14 acceptance against the actual
`cli-config.yaml.example` in the image.*

### 5.2 Secret — `hermes-secrets`

Four values — none committed to git:
- `LITELLM_BASE_URL` — the LiteLLM router's base URL (from `~/opencode.json`).
- `LITELLM_MODEL` — the default model ID per the operator's router (this deployment uses
  `smart-coder`).
- `LITELLM_API_KEY` — the router API key (from `~/opencode.json`).
- `API_SERVER_KEY` — the bearer token guarding the `:8642` API (operator-chosen).

Created **out-of-band** by `set-secret` — a script that reads all four values from
environment variables, ensures the `hermes` namespace exists, and applies the Secret
idempotently:

```sh
kubectl create secret generic hermes-secrets -n hermes \
  --from-literal=LITELLM_BASE_URL="${LITELLM_BASE_URL}" \
  --from-literal=LITELLM_MODEL="${LITELLM_MODEL}" \
  --from-literal=LITELLM_API_KEY="${LITELLM_API_KEY}" \
  --from-literal=API_SERVER_KEY="${API_SERVER_KEY}" \
  --dry-run=client -o yaml | kubectl apply -f -
```

The Secret is **not** committed and **not** Argo-managed; the `Deployment` references it
by name and injects keys as environment variables (`secretKeyRef`).

### 5.3 Deployment environment

- **Init container** env: `LITELLM_BASE_URL` + `LITELLM_MODEL` from `hermes-secrets` (for
  template substitution §5.1).
- **Main container** env: `API_SERVER_ENABLED=true`, `API_SERVER_HOST=0.0.0.0`,
  `HERMES_DASHBOARD=1`, plus `LITELLM_API_KEY` and `API_SERVER_KEY` from `hermes-secrets`.

---

## 6. Exposure & Networking

The hermes repo ships a **portable `ClusterIP` Service** named `hermes` in the `hermes`
namespace, exposing two ports against the Hermes pod:
- `:8642` — the OpenAI-compatible API.
- `:9119` — the web dashboard.

That is all the public repo carries — no cluster-specific exposure assumptions. Adopters
without MetalLB simply don't apply the overlay below; they have a portable ClusterIP they
can front with their own choice of Ingress / NodePort / port-forward.

**LAN access on this cluster** — a small **MetalLB LoadBalancer overlay** lives in
`labops/hermes-vip/`. It's a single `Service` manifest (`vip-hermes`) in the same
`hermes` namespace, selecting the same Hermes pods, with the
`metallb.universe.tf/allow-shared-ip: host` annotation. MetalLB places it on the NUC IP
`192.168.1.250` (shared with the Argo CD vip):
- `192.168.1.250:8642` — the API on the LAN.
- `192.168.1.250:9119` — the dashboard on the LAN.

This overlay is registered as a **second entry** in `labops/argo/services.yaml`
(`hermes-vip`), so Argo CD manages it alongside the Hermes deployment itself. Two
Services, same pods — `hermes` (ClusterIP) for in-cluster traffic, `vip-hermes`
(LoadBalancer) for LAN.

Plain HTTP on the LAN. The **API** is guarded by the `API_SERVER_KEY` bearer token. The
**dashboard's** auth posture is verified at implementation; if unauthenticated and LAN
exposure is unwanted, the dashboard port is dropped from `vip-hermes` (reached via
`kubectl port-forward` on the ClusterIP instead) — the API keeps the LoadBalancer either
way.

**Egress** — Hermes calls out to the remote LiteLLM router over HTTPS. Pod egress works on
this cluster (no NetworkPolicy; host firewalld disabled) — no extra configuration.

---

## 7. Data Flow, Failure Modes & Verification

### Data flow
1. *One-time:* run `set-secret` with `LITELLM_API_KEY` + `API_SERVER_KEY` in the env →
   creates `hermes-secrets`.
2. Add the `hermes` and `hermes-vip` entries to `labops/argo/services.yaml` (and the
   `labops/hermes-vip/service.yaml` overlay manifest), commit + push → the `services`
   ApplicationSet generates two Applications → Argo CD syncs the Hermes manifests and the
   MetalLB LoadBalancer overlay.
3. The pod starts: init container seeds `config.yaml` (first boot only) → `hermes gateway
   run` reads config + the env keys → serves `:8642` and `:9119`.
4. Steady state: a client calls `:8642` with the bearer token → Hermes's agent loop →
   calls the LiteLLM router (`smart-coder`) → responds; skills/sessions/memory persist to
   the PVC.

### Failure modes
- **Secret absent** — the pod will not start until `hermes-secrets` exists; Argo shows the
  app Progressing. Self-corrects when `set-secret` is run. Running step 1 before step 2 is
  cleanest, but order is not fatal.
- **Router unreachable / bad key** — the pod runs; agent *requests* fail at inference time,
  visible in logs and the dashboard. Not a crash.
- **Pod restart** — the PVC persists `/opt/data`; Hermes resumes with its
  skills/sessions/memory. `replicas: 1` + an RWO `local-path` PVC is correct for a
  single-node stateful agent.
- Argo CD self-heal corrects drift; deleting the registry entry prunes Hermes.

### Verification
- Manifests — `kubectl apply --dry-run`; the `set-secret` script — `shellcheck`.
- The `Deployment` carries liveness + readiness probes on `GET /health` (`:8642`).
- **Acceptance (end-to-end):** `set-secret` applied → registry entries added → Argo
  generates `hermes` + `hermes-vip`, both sync Healthy, the pod reaches Ready → call
  `192.168.1.250:8642/v1/models` and a small `/v1/chat/completions` with the bearer token
  and confirm a response — exercising the full chain Hermes → router → `smart-coder` — and
  load the dashboard at `192.168.1.250:9119`.

---

## 8. Risks & Notes

- **`config.yaml` schema** — the exact key for the env-referenced API key and any other
  mandatory fields are pinned against Hermes's config docs at implementation; the design
  principle (key value never in the ConfigMap) is fixed.
- **Generic public deployment template** — the repo carries **no operator-specific
  values**: URL + model + keys all live in the operator's Secret; cluster-specific
  exposure (MetalLB LoadBalancer) lives as an overlay in the operator's GitOps repo. The
  only committed defaults are the namespace name (`hermes`) and the pod's resource sizes
  — sensible defaults; adopters who need different just edit. The repo is fully reusable
  without forking for the common case.
- **Dashboard auth** — unverified; confirmed at implementation, with the port-forward
  fallback (§6) if it is unauthenticated.
- **Hermes owns `config.yaml`** after first boot — re-seeding requires updating the live
  file or recreating the PVC.
- **Hermes executes shell commands and code inside its own pod** — the pod is the blast
  radius. Acceptable for a personal homelab agent; noted as a security property.
- **Image pinned** — `nousresearch/hermes-agent` releases rapidly; upgrades are a
  deliberate manifest edit.
- **The LiteLLM router is an external dependency** — Hermes's inference availability tracks
  the router's.
