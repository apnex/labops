# Hermes Agent Platform — Build Roadmap

- **Created:** 2026-05-22
- **Status:** Planning — Phase A (research) **not yet started**.
- **Nature:** Multi-session effort. This is a **living document** — keep §8 (Status / Progress Log) current as phases complete, so any session can resume.

---

## 1. Goal

Deploy a **persistent Hermes agent** (`github.com/nousresearch/hermes-agent`) on the NUC's
k3s cluster, **fully GitOps-managed** through Argo CD. Hermes runs as an agent on the
**kagent** runtime, and calls a remote OpenAI-compatible **LiteLLM router** for LLM
inference.

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

## 5. Layering — HYPOTHESIS (pending Phase A)

This ordering is a **pre-research hypothesis**. Phase A confirms or revises it — in
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
