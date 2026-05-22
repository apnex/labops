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
  operator-specific values are committed; all per-deployment specifics (the LiteLLM
  router's base URL, API key, API server key) live in the operator's Secret.

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
| 9 | Model | Default `smart-coder` (Claude Opus 4.7 via the LiteLLM router) |
| 10 | Secrets | Manually-applied `hermes-secrets` Secret with **three** values — `LITELLM_BASE_URL`, `LITELLM_API_KEY`, `API_SERVER_KEY` — created out-of-band by the `set-secret` script from env vars; not in git, not Argo-managed |
| 11 | Exposure | One MetalLB LoadBalancer Service, `allow-shared-ip: host`, on the NUC IP `192.168.1.250`, ports 8642 + 9119 |
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

### 4.2 Registry entry (added to `labops/argo/services.yaml`)

```yaml
- name: hermes
  type: git
  repoURL: https://github.com/apnex/hermes
  gitPath: manifests
  revision: main
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
- **`Service` hermes** — `LoadBalancer` (§6).

---

## 5. Config & Secrets

### 5.1 `config.yaml` — templated, seeded, then Hermes-owned

The LiteLLM router's **base URL** is operator-specific (each adopter has a different
router), so it does not live in the public repo. The ConfigMap holds a **template**; the
init container substitutes the URL at first boot from a Secret-sourced env var. Hermes
then reads and *mutates* `/opt/data/config.yaml` at runtime, so the file lives on the PVC,
not on a mounted ConfigMap.

**ConfigMap `hermes-config`** — holds `config.yaml.tpl`:

```yaml
model:
  provider: custom
  base_url: @LITELLM_BASE_URL@
  default: smart-coder
  key_env: LITELLM_API_KEY      # Hermes reads the key from this env var at runtime
```

**Init container** (busybox) — mounts the ConfigMap at `/seed` and the PVC at `/opt/data`;
gets `LITELLM_BASE_URL` from the Secret. On first boot (file absent) it substitutes the
placeholder and writes the file; on later boots it leaves the file alone:

```sh
if [ ! -f /opt/data/config.yaml ]; then
  sed -e "s|@LITELLM_BASE_URL@|${LITELLM_BASE_URL}|g" \
    /seed/config.yaml.tpl > /opt/data/config.yaml
fi
```

First boot writes the rendered `config.yaml`; subsequent boots keep Hermes's
runtime-evolved version. **Consequence:** changing the template (or the operator's
`LITELLM_BASE_URL`) after first deploy does not affect a running instance — update the
live file (`hermes config set`) or recreate the PVC.

The router **API key is never written to a file** — it stays in the Secret, is injected
into the main container as the `LITELLM_API_KEY` env var, and `config.yaml`'s
`key_env: LITELLM_API_KEY` tells Hermes to read it from there. Exact `config.yaml` key
syntax (`key_env` or equivalent) is confirmed against Hermes's docs at implementation;
the principle is fixed: **URL and key never in the public repo.**

### 5.2 Secret — `hermes-secrets`

Three values — none committed to git:
- `LITELLM_BASE_URL` — the LiteLLM router's base URL (from `~/opencode.json`).
- `LITELLM_API_KEY` — the router API key (from `~/opencode.json`).
- `API_SERVER_KEY` — the bearer token guarding the `:8642` API (operator-chosen).

Created **out-of-band** by `set-secret` — a script that reads all three values from
environment variables, ensures the `hermes` namespace exists, and applies the Secret
idempotently:

```sh
kubectl create secret generic hermes-secrets -n hermes \
  --from-literal=LITELLM_BASE_URL="${LITELLM_BASE_URL}" \
  --from-literal=LITELLM_API_KEY="${LITELLM_API_KEY}" \
  --from-literal=API_SERVER_KEY="${API_SERVER_KEY}" \
  --dry-run=client -o yaml | kubectl apply -f -
```

The Secret is **not** committed and **not** Argo-managed; the `Deployment` references it
by name and injects keys as environment variables (`secretKeyRef`).

### 5.3 Deployment environment

- **Init container** env: `LITELLM_BASE_URL` from `hermes-secrets` (for templating §5.1).
- **Main container** env: `API_SERVER_ENABLED=true`, `API_SERVER_HOST=0.0.0.0`,
  `HERMES_DASHBOARD=1`, plus `LITELLM_API_KEY` and `API_SERVER_KEY` from `hermes-secrets`.

---

## 6. Exposure & Networking

One `Service` of type `LoadBalancer` with `metallb.universe.tf/allow-shared-ip: host`, so
MetalLB places it on the single NUC IP **`192.168.1.250`** (shared with the Argo CD vip).
Two ports:
- `192.168.1.250:8642` → the OpenAI-compatible API.
- `192.168.1.250:9119` → the web dashboard.

Plain **HTTP** on the LAN. The **API** is guarded by the `API_SERVER_KEY` bearer token. The
**dashboard's** own auth posture is verified at implementation; if it is unauthenticated
and LAN-exposure is unwanted, the dashboard port is dropped from the LoadBalancer and
reached via `kubectl port-forward` instead — the API keeps the LoadBalancer either way.

**Egress:** Hermes calls out to the remote LiteLLM router over HTTPS. Pod egress works on
this cluster (no NetworkPolicy; host firewalld disabled) — no extra configuration.

---

## 7. Data Flow, Failure Modes & Verification

### Data flow
1. *One-time:* run `set-secret` with `LITELLM_API_KEY` + `API_SERVER_KEY` in the env →
   creates `hermes-secrets`.
2. Add the `hermes` entry to `labops/argo/services.yaml`, commit + push → the `services`
   ApplicationSet generates a `hermes` Application → Argo CD syncs the `apnex/hermes`
   manifests.
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
- **Acceptance (end-to-end):** `set-secret` applied → registry entry added → Argo generates
  `hermes`, syncs Healthy, the pod reaches Ready → call `:8642/v1/models` and a small
  `:8642/v1/chat/completions` with the bearer token and confirm a response — exercising the
  full chain Hermes → router → `smart-coder` — and load the dashboard at `:9119`.

---

## 8. Risks & Notes

- **`config.yaml` schema** — the exact key for the env-referenced API key and any other
  mandatory fields are pinned against Hermes's config docs at implementation; the design
  principle (key value never in the ConfigMap) is fixed.
- **Generic public deployment template** — the repo is intended as a reusable template
  others can adopt: all operator-specific values (URL, keys) live in the operator's
  Secret. The remaining defaults that *are* committed (model name `smart-coder`, the
  MetalLB `LoadBalancer` + `allow-shared-ip: host` exposure on a single host IP) are
  deliberately opinionated defaults — adopters whose LiteLLM router uses different model
  IDs, or who run a non-MetalLB cluster, would override via Kustomize/fork. Worth a
  conscious review-call before lock-in.
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
