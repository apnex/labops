# Hermes Agent Platform — Build Roadmap

- **Created:** 2026-05-22
- **Status:** Planning — Phase A (research) **not yet started**.
- **Nature:** Multi-session effort. This is a **living document** — keep §8 (Status / Progress Log) current as phases complete, so any session can resume.

---

## 1. Goal

Deploy a **persistent Hermes agent** (`github.com/NousResearch/hermes-agent`) on the NUC's
k3s cluster, **fully GitOps-managed** through Argo CD. Hermes runs as a **standalone
deployment** (Phase A confirmed it is a self-contained application, not a kagent agent)
and calls a remote OpenAI-compatible **LiteLLM router** for LLM inference.

## 2. Foundation already in place (Layer 0)

Built earlier this effort — see `docs/superpowers/specs/`:

- k3s on the NUC + MetalLB + local-path storage + metrics-server
  (`2026-05-22-k3s-host-install-design.md`).
- Argo CD + the `services.yaml` GitOps registry / ApplicationSet
  (`2026-05-22-gitops-service-registry-design.md`).

Everything below is **declared through Argo CD** on top of this foundation.

## 3. Components (the moving parts)

| Component | Source | Role | Home |
|-----------|--------|------|------|
| **kagent** | `github.com/kagent-dev/kagent` | Agent runtime — provides the CRDs Hermes is defined on | `labops/` (e.g. `labops/kagent/`) |
| **kgateway** | `github.com/kgateway-dev/kgateway` | Gateway-API / API gateway — a kagent integration | `labops/` |
| **agentgateway** | `agentgateway.dev` | Agent-native gateway — a kagent integration; has a documented ArgoCD install | `labops/` |
| **Hermes agent** | `github.com/nousresearch/hermes-agent` | The target workload — defined as a kagent agent | **its own dedicated repo** |
| **LiteLLM router** | external (per `~/opencode.json`) | OpenAI-compatible LLM router Hermes calls | already deployed — **not** deployed by us |

## 4. Approach — three phases

**Phase A — Research & dependency mapping.**
Investigate each component: install method (Helm / manifests / operator), CRDs exposed,
hard vs optional dependencies, ArgoCD-integration shape, and the parametrisation surface.
Read `~/opencode.json` to understand the LiteLLM router contract. **Output:** a verified
dependency graph + a parametrisation inventory.

**Phase B — Decomposition & ordering.**
Turn the dependency graph into a set of **ordered, independently-buildable sub-projects**.
For each: its ApplicationSet grouping, its repo home, and its position in the dependency
order. Update §5 below with the *confirmed* layering.

**Phase C — Build, layer by layer.**
Each layer is a full **brainstorm → spec → plan → build** cycle (the cadence used for the
k3s and registry work). Bottom-up; **Hermes last**. Each layer's spec lands in
`docs/superpowers/specs/`.

## 5. Layering — HYPOTHESIS (⚠️ SUPERSEDED by Phase A)

> **⚠️ SUPERSEDED.** Phase A research found Hermes does **not** layer on kagent — they are
> independent systems, not a stack. See §8 and §9. The forward plan is re-cut after the
> scope decision.

This ordering was a **pre-research hypothesis**. Phase A confirms or revises it — in
particular whether kgateway *and* agentgateway are both required, or one is optional.

- **L0** — Foundation: k3s + Argo CD + registry. ✅ Done.
- **L1** — Gateway / networking base (kgateway and/or Gateway-API CRDs). *Need confirmed by research.*
- **L2** — agentgateway.
- **L3** — kagent platform + CRDs.
- **L4** — Hermes agent (own repo), defined as a kagent agent, pointed at the LiteLLM router.

## 6. GitOps placement

- Infra layers (L1–L3) live under `labops/` and are declared via Argo CD — likely a
  dedicated **`platform` ApplicationSet** group, kept separate from the `services`
  registry so platform infra and apps are curated independently.
- **Hermes** (L4) lives in its **own dedicated repo**, referenced as a `services.yaml`
  registry entry.
- All layers actuated by Argo CD on the existing cluster.

## 7. Open questions (resolve in Phase A / with the user)

- Are **kgateway and agentgateway both required** by kagent, or is one optional? *(research)*
- Is this **kagent-as-a-general-agent-platform** (more agents after Hermes), or scoped
  just to Hermes? *(user)*
- Does the **Hermes dedicated repo** exist yet, or is it to be created? *(user)*
- Install mechanics per component — Helm chart vs raw manifests vs operator — and how each
  maps cleanly onto an ApplicationSet. *(research)*
- LiteLLM router contract — endpoint, model names, auth — from `~/opencode.json`. *(research)*

## 8. Status / Progress Log

_Update this section as work proceeds across sessions._

- **2026-05-22** — Roadmap created. Phase A not yet started. **Next action:** begin Phase A research.
- **2026-05-22 (later)** — Phase A research complete (§9). **KEY FINDING:** Hermes is a
  self-contained agent *application*, not a kagent agent — it cannot run "on top of"
  kagent. kagent / kgateway / agentgateway are independent and optional; **none are
  required for Hermes.** The §5 L0→L4 layering is therefore invalid. **Repo decision:**
  new infra lives in its own dedicated repo, separate from `labops`. **Pending:** scope
  decision — whether kagent stays in scope as a separate platform, or the effort is
  scoped to Hermes alone. Forward plan (§3/§5/§6) to be re-cut once decided.
- **2026-05-22 (later 2)** — Follow-up source-level research on Hermes↔kagent integration
  (§9): verified there is **no real integration path** and no value in integrating for the
  Hermes goal. Scope strongly points to **Hermes standalone**; kagent only if wanted as a
  separate platform on its own merits.
- **2026-05-22 (later 3)** — **SCOPE SETTLED.** Build GitOps-deployed **Hermes standalone**
  in its **own dedicated repo** (separate from `labops`). **kagent parked** — kept as a
  separate future effort to brainstorm on its own merits, not dropped. Now brainstorming
  the Hermes design (§3/§5/§6 above are the superseded original hypothesis — this log is
  the authoritative current state).
- **2026-05-22 (later 4)** — Hermes deployment design brainstormed; spec written and
  committed: `docs/superpowers/specs/2026-05-22-hermes-deployment-design.md`. Awaiting
  spec review, then the implementation plan.
- **2026-05-22 (later 5)** — Spec approved (with refinements: `LITELLM_BASE_URL` +
  `LITELLM_MODEL` moved to the Secret, repo ships portable `ClusterIP` with a `vip-hermes`
  MetalLB overlay in `labops/hermes-vip/`). **Implementation plan written:**
  `docs/superpowers/plans/2026-05-22-hermes-deployment.md`. Next: execution.

## 9. Phase A Findings (research, 2026-05-22)

**Hermes** (`NousResearch/hermes-agent`, v2026.5.16) — self-contained Python agent
*application*; image `nousresearch/hermes-agent`. Runs `hermes gateway run`;
OpenAI-compatible API on `:8642`. Stateful — skills/sessions/memory under `/opt/data`
(needs a PVC; `replicas: 1`). LLM endpoint set in `config.yaml` (`model.provider: custom`,
`base_url`, `api_key`); env-var config removed, so `config.yaml` must be pre-seeded
(ConfigMap + init container). **Not a kagent agent** (own runtime; no A2A protocol).
Deploy as a plain Deployment + PVC + ConfigMap + Secret + Service. No external DB.

**kagent** (`kagent-dev/kagent`, v0.9.4) — Kubernetes-native AI-agent framework; CRDs
`kagent.dev/v1alpha2` (Agent, ModelConfig, …). Install: 4 OCI Helm charts under
`oci://ghcr.io/kagent-dev/kagent/helm/` (`kagent-crds` first, then `kagent`). **Hard dep:
PostgreSQL + pgvector** (bundled chart for dev). Does **not** require kgateway or
agentgateway. ArgoCD: CRD chart needs `ServerSideApply=true` (oversized CRDs — same
gotcha hit with Argo CD itself). Supports arbitrary OpenAI-compatible endpoints via the
`ModelConfig` CR (`provider: OpenAI` + `openAI.baseUrl`).

**kgateway** (`kgateway-dev/kgateway`, v2.3.1) — Envoy-based API gateway (K8s Gateway
API). 2 OCI Helm charts (`cr.kgateway.dev/…`) + upstream Gateway API CRDs prerequisite
(k3s ships none). Optional LLM-egress/guardrails layer — **not required**.

**agentgateway** (`agentgateway.dev`, v1.2.1) — Rust agent-native proxy (MCP / A2A / LLM).
2 OCI Helm charts (`cr.agentgateway.dev/charts`) + Gateway API CRDs. Has a documented
ArgoCD install. Independent of kgateway since v1.0. Optional governance layer — **not
required**.

**LiteLLM router** (from `~/opencode.json`) — remote OpenAI-compatible endpoint (Google
Cloud Run URL); API key present; exposes 3 models: `smart-fast` (Gemini 3 Flash),
`smart-reasoning` (Gemini 3.1 Pro), `smart-coder` (Claude Opus 4.7). Hermes points its
`config.yaml` `base_url` at it; the key goes into a k8s Secret.

**Implication:** kagent / kgateway / agentgateway are not a foundation for Hermes — they
are a separate, optional agentic-platform track. The Hermes goal is met by Hermes alone.

**Hermes ↔ kagent integration — verified at source level (follow-up research).** kagent
has **no shipped Hermes integration**: "Hermes" appears once in kagent's code as a
`// Future backends (e.g. Hermes)` comment, and a Solo.io blog lists it only as an example
of the agent-harness *category*. Hermes **cannot** be a kagent `AgentHarness` (backend
hard-coded to `openclaw`/`nemoclaw`) nor a BYO `Agent` (BYO needs the A2A protocol; Hermes
speaks ACP + MCP + an OpenAI-compatible API, not A2A). The only clean path is kagent
*using* Hermes's `:8642` API as an LLM backend — which bypasses Hermes's own loop, memory,
and skills. **Conclusion: integrating Hermes with kagent adds no value for the Hermes goal;
kagent is a separate optional platform, not a Hermes substrate.**
