# k3s Host Install — Design Spec

- **Date:** 2026-05-22
- **Status:** Approved (pending spec review)
- **Topic:** Fresh, idempotent k3s install for a persistent physical host (initial target: Intel NUC 15+ Pro, Fedora 44), reusing and extending existing `labops` automation.

---

## 1. Context & Problem

The `labops` repo automates self-assembling **ephemeral CentOS 7 VMs** that bootstrap
themselves over HTTP from `labops.sh` and evolve through staged "node" layers
(`base` → `docker` → `rke`/`k3s` → `labops`/Argo CD).

The new requirement is different: install k3s on a **persistent, physical host** —
an Intel NUC 15+ Pro running **Fedora 44**. The existing `k3s/` automation mostly
works but carries VM-era assumptions (CentOS 7, curl-pipe-from-`labops.sh`, fire-once
semantics) and at least one outright bug. This spec defines automation that installs a
usable single-node k3s cluster on such a host, while keeping every existing module
independently runnable and the VM evolution path intact.

The repo's design philosophy — **clean sovereign modularity**: small single-purpose
scripts, independently runnable, no hidden logic, minimal external dependencies — is
treated as a hard constraint on this design.

---

## 2. Goals & Non-Goals

### Goals
- Install k3s + a practical add-on set on a persistent host with one entrypoint.
- End state: k3s + **MetalLB** (LoadBalancer support) + **local-path storage** + **metrics-server**.
- Storage and metrics-server are provided by **k3s's own bundled components**, but must
  be **cleanly toggleable on/off** so other providers (e.g. Longhorn) can be tested.
- Idempotent: safe to re-run for tweaks, recovery, or upgrades.
- A real teardown that resets the host for a clean reinstall.
- Hybrid execution: run locally from a clone, *and* keep every module independently
  runnable standalone / via `curl | sh`.
- Multi-OS safe: must not break the existing VM path (Rocky, Fedora, CentOS, Alpine)
  or the existing RKE-based chain.

### Non-Goals
- Argo CD / the application catalogue (explicitly out of scope).
- Multi-node / HA k3s.
- An ingress controller — `traefik` stays disabled; services are exposed directly as
  `LoadBalancer` via the `vip-*` pattern.
- Reproducible version pinning — the user chose to **track latest channels**.
- Rewriting the VM evolution / `stages` model.
- Unrelated refactoring of modules not touched by this work.

---

## 3. Decisions

Settled during brainstorming:

| # | Decision | Choice |
|---|----------|--------|
| 1 | Scope | k3s + MetalLB + (k3s-bundled storage + metrics, toggleable). No Argo CD. |
| 2 | Execution model | Hybrid — local-first entrypoint; modules also runnable standalone / via `curl\|sh` |
| 3 | Firewall | Disable firewalld; SELinux left **enforcing** (k3s installer adds `k3s-selinux`) |
| 4 | Versioning | Track latest channels; MetalLB follows current official steps (native manifest, latest tag) |
| 5 | Re-run behaviour | Idempotent entrypoint + a real teardown |
| 6 | Orchestrator | New `k3s/up` — thin composition only, no install logic |
| 7 | OS variability | Quarantined to a single OS-aware module (`k3s/prepare`); everything else OS-agnostic |
| 8 | Wait-loop dedup | In the modules this work edits, replace inline "wait for API" loops with `healthcheck/k8s-local` |
| 9 | Composition style | `k3s/up` holds a declarative component-toggle config + ordered module list |
| 10 | Module headers | Every new/edited module gets a standard 4-line header block |
| 11 | Component toggle | `K3S_STORAGE` / `K3S_METRICS` (on/off) drive k3s `--disable` flags *and* which modules run; bundled-on by default |
| 12 | Storage strategy | Use k3s's bundled local-path; `storage/install` becomes detect-and-skip + always ensures the `standard` StorageClass |
| 13 | Metrics strategy | Use k3s's bundled metrics-server; upstream `metrics/*` drop out of the k3s chain, untouched, for the RKE path / `K3S_METRICS=off` |

### 3.1 Key findings that shaped the design

- **k3s bundles `local-storage` (rancher local-path-provisioner) and `metrics-server`**
  as packaged components. Installing upstream copies on k3s is redundant. The existing
  `k3s/runonce.sh` already reflected this (k3s + MetalLB only).
- **The repo's app manifests hard-code `storageClassName: "standard"`**
  (`planespotter*/ps-sql.yaml`, `apps/planespotter/ps-pvc.yaml`). k3s's bundled
  StorageClass is named `local-path`. A `standard` class must therefore still be
  created — aliasing the same `rancher.io/local-path` provisioner.
- **MetalLB bug:** `metallb/prepare` creates only an `IPAddressPool`. Since MetalLB
  v0.13 (CRD-based config — including the currently-pinned v0.13.10), L2 mode also
  requires an **`L2Advertisement`**, or LoadBalancer IPs are allocated but never
  ARP-advertised → services unreachable. Must be fixed.
- **The host-IP overload mechanism:** every `vip-*` service carries the annotation
  `metallb.universe.tf/allow-shared-ip: host`. All `LoadBalancer` services share the
  single host IP (keyed `host`), distinguished by port. This is still supported in
  current MetalLB — the `vip-*` manifests need **no changes**.

---

## 4. Architecture & File Layout

OS-specificity is quarantined to one module. The orchestrator is thin: it owns the
component-toggle config, ordering, logging, and a verification call — no install logic.

```
k3s/
  up           NEW   orchestrator — toggle config + declarative module list + logging
  prepare      NEW   OS-aware host prep (the ONLY OS-specific module)
  verify       NEW   toggle-aware standalone cluster health assertions
  install      EDIT  k3s install; the --disable list is now driven by a K3S_DISABLE input
  remove       EDIT  upgraded from 1-liner to full teardown (+ opt-in --purge)
  runonce.sh   EDIT  thinned to a VM-boot shim: exec k3s/up, then write startup.done
  README.md    NEW   short usage doc
metallb/
  install      EDIT  native manifest @ latest release tag; dedupe wait-loop
  prepare      EDIT  fix `route`->`ip route`; ADD L2Advertisement; dedupe wait-loop; printf '%s'
  remove       keep
storage/
  install      EDIT  detect-and-skip the provisioner; always ensure the `standard` SC; dedupe wait-loop
metrics/
  install      keep  NOT in the k3s chain — unchanged, sovereign (RKE path / K3S_METRICS=off)
  patch        keep  same
healthcheck/
  k8s-local            EDIT  add optional WAIT_TIMEOUT (default unbounded)
  k8s-deployment-ready EDIT  add optional WAIT_TIMEOUT (default unbounded)
  (others)             keep
```

### Blast radius
All new behaviour lives in new files. Existing modules receive only
**backward-compatible** edits: an *optional* `WAIT_TIMEOUT` (default = current unbounded
behaviour), a Fedora bug fix, the MetalLB `L2Advertisement` fix, a detect-and-skip guard
in `storage/install`, and a parameterised `--disable` in `k3s/install` (default
preserves today's `servicelb,traefik`). No existing module changes its public contract;
the RKE chain and VM path keep working.

---

## 5. The Hybrid Resolver (data flow)

Modules that call siblings use a small resolver instead of a hardcoded
`https://labops.sh/...` URL:

```bash
LABOPS_BASE="${LABOPS_BASE:-https://labops.sh}"
run() {
    local module="$1"; shift
    if [[ -n "${LABOPS_ROOT:-}" && -f "${LABOPS_ROOT}/${module}" ]]; then
        bash "${LABOPS_ROOT}/${module}" "$@"
    else
        curl -fsSL "${LABOPS_BASE}/${module}" | bash -s -- "$@"
    fi
}
```

- `k3s/up` sets `LABOPS_ROOT="$(cd "$(dirname "$0")/.." && pwd)"`, **exports** it, and
  `export -f run`. Child modules invoked via `bash` inherit both — so a locally-run
  module resolves its own siblings locally too.
- Each module needing the resolver carries a **self-define guard** so it still works
  standalone: `command -v run >/dev/null 2>&1 || run() { ...inline definition... }`.
- `k3s/up` exports `KUBECONFIG=/root/.kube/config` once; downstream modules inherit it.
- **Side benefit:** the resolver invokes modules with `bash` / `bash -s`, not `| sh` —
  removing latent Alpine breakage where bash-isms were run under busybox `ash`.

---

## 6. Component Specifications

Every new/edited module begins with a standard header:

```bash
## module: <dir/name>
## purpose: <one line>
## inputs:  <env vars consumed, or ->
## needs:   <sibling modules called, or ->
```

### 6.1 `k3s/up` — orchestrator
- **Purpose:** install the full k3s host stack, idempotently.
- `set -euo pipefail`; logs via `tee -a /root/k3s-install.log`.
- Resolves/exports `LABOPS_ROOT`; defines/exports `run`; exports
  `KUBECONFIG=/root/.kube/config` and `WAIT_TIMEOUT=300`.
- **Component-toggle config** (env-overridable) drives both k3s `--disable` flags and
  the module list:

  ```bash
  ## k3s/up — component config (override via env)
  : "${K3S_STORAGE:=on}"   # on  -> k3s bundled local-path + a 'standard' StorageClass alias
                            # off -> k3s --disable=local-storage  (bring your own: Longhorn, etc.)
  : "${K3S_METRICS:=on}"   # on  -> k3s bundled metrics-server
                            # off -> k3s --disable=metrics-server

  DISABLE="servicelb,traefik"                       # always — MetalLB replaces servicelb
  MODULES=( k3s/prepare k3s/install )
  [[ $K3S_STORAGE == off ]] && DISABLE+=",local-storage"
  [[ $K3S_METRICS == off ]] && DISABLE+=",metrics-server"
  MODULES+=( metallb/install metallb/prepare )
  [[ $K3S_STORAGE == on  ]] && MODULES+=( storage/install )
  MODULES+=( k3s/verify )

  export K3S_DISABLE="$DISABLE" K3S_STORAGE K3S_METRICS
  for m in "${MODULES[@]}"; do run "$m"; done
  ```

- Adding/removing a stage is a one-line edit. Any module exiting non-zero aborts the run.
- Idempotent: every listed module is idempotent.

### 6.2 `k3s/prepare` — OS-aware host prep (the only OS-specific module)
- **Purpose:** make the host ready for k3s.
- Sources `/etc/os-release` for a log header; detects init system:
  ```bash
  if   command -v systemctl >/dev/null; then INIT=systemd
  elif command -v rc-update >/dev/null; then INIT=openrc
  fi
  case "$INIT" in
    systemd) systemctl disable --now firewalld 2>/dev/null
             systemctl mask firewalld 2>/dev/null ;;          # Rocky/CentOS/Fedora
    openrc)  rc-update add cgroups boot
             rc-service cgroups start ;;                       # Alpine — k3s needs cgroups
  esac
  ```
- Sanity checks: confirm `curl` and `ip` (iproute) are present; report `getenforce`.
- Light OS check: warn (do **not** hard-fail) on an unrecognised OS.
- Idempotent. SELinux left **enforcing** — the k3s installer pulls `k3s-selinux` itself.

### 6.3 `k3s/install` — k3s install — EDIT
- A leaf script — calls no siblings.
- **Edit:** the `--disable` list is now driven by a `K3S_DISABLE` env var (default
  `servicelb,traefik`, preserving today's behaviour for standalone callers):
  `curl -fsSL https://get.k3s.io | sh -s - --disable=${K3S_DISABLE}`.
- Otherwise unchanged: `stable` channel, waits for `/etc/rancher/k3s/k3s.yaml`, copies
  it to `/root/.kube/config`.

### 6.4 `k3s/verify` — toggle-aware health assertions
- **Purpose:** assert the cluster reached its intended end state; independently re-runnable.
- Reads `K3S_STORAGE` / `K3S_METRICS` so it only checks what was requested.
- Checks (each failure → non-zero exit, clear message):
  - node(s) report `Ready`; `kube-system` pods all `Running`/`Completed`
  - MetalLB `controller` deployment Ready in `metallb-system`
  - `IPAddressPool` `host-pool` **and** `L2Advertisement` exist in `metallb-system`
  - if `K3S_STORAGE=on`: StorageClass `standard` exists
  - if `K3S_METRICS=on`: `kubectl top node` returns data
- Called last by `k3s/up`; also runnable standalone anytime.

### 6.5 `k3s/remove` — teardown — EDIT
- **Purpose:** reset the host for a clean reinstall.
- Runs `/usr/local/bin/k3s-uninstall.sh` if present (no-op if k3s absent);
  removes `/root/.kube/config`.
- **PV data is opt-in to delete.** local-path volume data under
  `/opt/local-path-provisioner` survives uninstall. By default `remove` prints the path
  and leaves it; `k3s/remove --purge` additionally deletes that directory.
- firewalld is left as `prepare` set it (masked) — teardown does not silently re-enable it.

### 6.6 `metallb/install` — EDIT
- Aligned to MetalLB's current install steps: apply the **native** manifest
  (`metallb-native.yaml`) — correct for pure L2, single-node, no BGP (FRR-K8s mode is
  only for BGP). Resolve the **latest release tag** dynamically (GitHub API + `jq`).
- `strictARP` is a prerequisite *only* for IPVS kube-proxy; k3s defaults to iptables and
  runs kube-proxy in-process, so it does not apply here — `metallb/install` notes this
  and skips it.
- Replace the inline "wait for API" loop with `run healthcheck/k8s-local`.

### 6.7 `metallb/prepare` — EDIT
- **Fedora bug fix:** replace `route | grep ^default` (needs `net-tools`, absent on
  Fedora 44) with an `ip route` based lookup of the default-route interface and IPv4 address.
- **MetalLB bug fix:** apply an **`L2Advertisement`** (no pool selector → advertises all
  pools) alongside the existing `IPAddressPool` (`host-pool`, host IP `/32`). Without it,
  LoadBalancer IPs are allocated but never advertised.
- Replace the inline wait-loop with `run healthcheck/k8s-local`.
- Hardening: `printf '%s'` instead of `printf "${VAR}"` when emitting manifests.

### 6.8 `storage/install` — EDIT
- **Detect-and-skip:** if a `rancher.io/local-path` provisioner is already present
  (as on k3s, which bundles `local-storage`), skip redeploying it; if absent (the
  RKE path), deploy it as today. This keeps one sovereign module working on both k3s
  and RKE.
- **Always** ensure the `standard` StorageClass (`provisioner: rancher.io/local-path`)
  so the `planespotter*` apps work regardless of cluster type.
- Replace the inline wait-loop with `run healthcheck/k8s-local`.
- Runs in the k3s chain only when `K3S_STORAGE=on`.

### 6.9 `metrics/install` & `metrics/patch` — unchanged
- **Not** part of the k3s chain — k3s's bundled metrics-server is used instead and is
  already correctly configured for k3s (the old `metrics/patch` forcing `--secure-port=4443`
  is stale and risks breaking modern probe ports).
- Left **as-is** as sovereign modules for the RKE path, or for a user who sets
  `K3S_METRICS=off` and wants the upstream metrics-server. Not edited by this work.

### 6.10 `healthcheck/k8s-local` & `healthcheck/k8s-deployment-ready` — EDIT
- Add an optional `WAIT_TIMEOUT` env var (seconds).
- **Default = `0` = unbounded** — identical to today's behaviour, so existing callers
  (`argo/`, etc.) are unaffected.
- When `WAIT_TIMEOUT > 0`, the loop exits non-zero with a clear timeout message once
  elapsed wait exceeds it. `k3s/up` sets `WAIT_TIMEOUT=300`.

### 6.11 `k3s/runonce.sh` — EDIT
- Thinned to a VM-boot shim: `exec k3s/up` (via the resolver), then write the
  `/root/startup.done` sentinel the VM stages expect.
- Net effect: the VM evolution path now also gets the toggle-driven stack, with `up` as
  the single source of truth. `up` itself stays host/OS-agnostic.

---

## 7. Cross-OS Handling

`runonce.sh` is portable today only because it does **zero** OS-specific work — it
delegates all OS variation to the `get.k3s.io` installer. This design preserves that by
quarantining every OS-specific action in `k3s/prepare`:

| Module | OS-specific? | Why |
|--------|--------------|-----|
| `k3s/prepare` | **Yes** | firewalld (systemd) vs cgroups service (OpenRC) |
| `k3s/install` | No | `get.k3s.io` auto-detects systemd vs OpenRC |
| `storage/install`, `metallb/*`, `k3s/verify` | No | pure `kubectl apply` / API calls |

`k3s/prepare` branches on **init system**, not distro name — Rocky, CentOS, Fedora all
collapse to the `systemd` branch; Alpine is the `openrc` branch. A branch that needs
nothing is a no-op.

**Alpine note:** the repo's scripts use bash features, so an Alpine host must have the
`bash` package installed — documented in `k3s/README.md` as an Alpine prerequisite.

---

## 8. Error Handling

- `k3s/up` runs `set -euo pipefail`; any module exiting non-zero aborts the run, with
  full output in `/root/k3s-install.log`.
- `WAIT_TIMEOUT=300` (set by `up`) bounds the otherwise-infinite healthcheck loops, so a
  broken install fails loudly rather than hanging.
- Re-running `up` after a partial failure resumes cleanly — every step is idempotent.
- `metallb/prepare` gates on the MetalLB controller being Ready before applying the
  `IPAddressPool` / `L2Advertisement`.
- `metallb/install` errors clearly if the latest-tag lookup fails, rather than applying
  an empty tag.

---

## 9. Verification & Testing Strategy

Infrastructure shell scripts have no meaningful unit-test surface; verification is
behavioural:

- **`k3s/verify`** — the toggle-aware end-state assertions of §6.4 are the functional test.
- **shellcheck** — lint gate on every new and edited script.
- **Idempotency test** — run `k3s/up` twice; the second run succeeds and changes nothing material.
- **Toggle test** — run with `K3S_STORAGE=off` and with `K3S_METRICS=off`; confirm the
  corresponding k3s component is absent and `k3s/verify` adapts.
- **Teardown test** — `k3s/remove` then `k3s/up` rebuilds a clean cluster.
- **Acceptance** — a real run of `k3s/up` on the Fedora 44 NUC, ending with `k3s/verify`
  green, and at least one `vip-*` `LoadBalancer` service reachable on the host IP.

---

## 10. Risks & Notes

- **MetalLB latest-tracking on single-node L2** — recent MetalLB releases (v0.14.8/
  v0.14.9) had a regression where the speaker failed to bind the LoadBalancer IP on
  single-node clusters. Current latest is v0.16.0. Tracking latest means a future
  re-run could land on a regressed release; the resolved tag is a one-line override in
  `metallb/install` if that happens.
- **MetalLB latest-tag resolution** depends on GitHub API reachability at install time.
- **Alpine `cgroups` runlevel** — `rc-update add cgroups boot` reflects current k3s /
  Alpine guidance (cgroup v2, OpenRC ≥ 3.19). The NUC target is Fedora; the Alpine path
  is exercised only via the VM evolution and should be validated there separately.
- **`runonce.sh` behaviour change** — pointing it at `up` changes the VM evolution
  stack to the toggle-driven one. Intended as an upgrade; called out for visibility.
- The NUC's k3s API binds the host IP; with firewalld disabled, port 6443 is reachable
  on the LAN. Acceptable for a lab host on a trusted network (decision #3).
