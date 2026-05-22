# k3s Host Install — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Install a usable single-node k3s cluster (k3s + MetalLB + bundled storage/metrics, toggleable) on a persistent Fedora 44 host, by extending the existing `labops` automation.

**Architecture:** A thin orchestrator (`k3s/up`) composes small sovereign modules via a hybrid local/remote resolver. OS-specific work is quarantined in `k3s/prepare`. k3s's own bundled `local-storage` and `metrics-server` are used by default, toggleable off via `K3S_STORAGE` / `K3S_METRICS`. MetalLB provides `LoadBalancer` support; all services share the single host IP via the existing `allow-shared-ip` annotation.

**Tech Stack:** Bash, k3s (`get.k3s.io`), MetalLB (native manifest), `kubectl`, `shellcheck` (lint).

**Reference spec:** `docs/superpowers/specs/2026-05-22-k3s-host-install-design.md`

---

## Conventions

- **Target host:** the Fedora 44 NUC this repo lives on (`/root/labops`). Tasks 1–12 only edit files; Tasks 13–15 modify the host.
- **Verification model:** infrastructure shell scripts are verified by `shellcheck` + `bash -n` syntax check, plus behavioral tests where feasible (Tasks 1, 9) and a real install acceptance run (Tasks 13–15). This follows §9 of the spec.
- **shellcheck gate:** every script must produce **no new error- or warning-level findings**. Pre-existing style/info findings on lines you did not change may be left as-is (noted per task where relevant).
- **Indentation (critical):** every shell script in this repo uses **TAB** indentation — preserve it. Copy each task's code block **verbatim**; never let an editor or formatter convert tabs to spaces. The only space-indented lines permitted are the **YAML bodies inside `<<EOF` heredocs** (`metallb/prepare`, `storage/install`) — YAML forbids tabs. The `<<-'EOF'` heredocs in `healthcheck/k8s-deployment-ready` rely on tab stripping; space indentation there breaks the script. After writing each script, verify indentation:
  - `metallb/prepare`, `storage/install`: `grep -nP '^ +\S' <file>` must show **only** YAML heredoc lines (e.g. `name:`, `addresses:`).
  - every other script: `grep -nP '^ +\S' <file>` must return **nothing**.
- **Commit footer:** every commit message ends with this footer line:
  `Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>`
- **Module header:** every new/edited script starts with the 4-line header shown in each task.
- All scripts keep `#!/bin/bash` and remain executable (`chmod +x` for new files).

## Prerequisites

- [ ] **Install `shellcheck`** (lint tool used by every task)

Run: `command -v shellcheck || sudo dnf install -y ShellCheck`
Expected: `shellcheck` resolves to a path (e.g. `/usr/bin/shellcheck`).

---

## Task 1: `healthcheck/k8s-local` — bounded wait

**Files:**
- Modify: `healthcheck/k8s-local`

- [ ] **Step 1: Replace the file with the bounded-wait version**

```bash
#!/bin/bash
## module: healthcheck/k8s-local
## purpose: block until the kube-system API responds
## inputs:  KUBECONFIG, WAIT_TIMEOUT (seconds; 0 = unbounded, default 0)
## needs:   -

WAIT_TIMEOUT="${WAIT_TIMEOUT:-0}"
ELAPSED=0

echo "[[ ${KUBECONFIG} ]]"
HEALTHY=$(kubectl -n kube-system get pods 2>/dev/null)
while [[ -z ${HEALTHY} ]]; do
	echo "socket [ localhost:6443 ] api [ no response ]"
	sleep 10
	ELAPSED=$((ELAPSED + 10))
	if [[ ${WAIT_TIMEOUT} -gt 0 && ${ELAPSED} -ge ${WAIT_TIMEOUT} ]]; then
		echo "[ K8S/LOCAL ] ERROR: api unreachable after ${WAIT_TIMEOUT}s" 1>&2
		exit 1
	fi
	HEALTHY=$(kubectl -n kube-system get pods 2>/dev/null)
done
echo "socket [ localhost:6443 ] api [ healthy ]"
```

- [ ] **Step 2: Lint**

Run: `shellcheck healthcheck/k8s-local`
Expected: no output, exit 0.

- [ ] **Step 3: Syntax check**

Run: `bash -n healthcheck/k8s-local`
Expected: no output, exit 0.

- [ ] **Step 4: Behavioral test — the timeout path fires**

Run: `time ( KUBECONFIG=/nonexistent WAIT_TIMEOUT=10 bash healthcheck/k8s-local ); echo "exit=$?"`
Expected: runs ~10 seconds, prints `ERROR: api unreachable after 10s`, then `exit=1`.

- [ ] **Step 5: Behavioral test — default is unbounded (no regression)**

Run: `grep -n 'WAIT_TIMEOUT:-0' healthcheck/k8s-local`
Expected: one match — confirms the default is `0`, i.e. existing callers (e.g. `argo/`) keep their original unbounded behavior.

- [ ] **Step 6: Commit**

```bash
git add healthcheck/k8s-local
git commit -m "healthcheck/k8s-local: add optional WAIT_TIMEOUT (default unbounded)"
```

---

## Task 2: `healthcheck/k8s-deployment-ready` — bounded wait

**Files:**
- Modify: `healthcheck/k8s-deployment-ready`

- [ ] **Step 1: Replace the file with the bounded-wait version**

```bash
#!/bin/bash
## module: healthcheck/k8s-deployment-ready
## purpose: block until all replicas of a deployment are READY
## inputs:  $1=RESOURCE $2=NAMESPACE (or RESOURCE/NAMESPACE env); WAIT_TIMEOUT (0=unbounded, default 0)
## needs:   -
# for a given deployment, checks that all replicas are in READY state

## defaults
VAR_SLEEP=5
WAIT_TIMEOUT="${WAIT_TIMEOUT:-0}"
ELAPSED=0
if [[ -n $1 ]]; then
	RESOURCE=$1
fi
if [[ -n $2 ]]; then
	NAMESPACE=$2
fi

function getDeploymentReady {
	local JSON
	JSON=$(kubectl -n "${NAMESPACE}" get deployment "${RESOURCE}" -o json)
	read -r -d '' FILTER1 <<-'EOF'
		.status.readyReplicas // empty
	EOF
	local READYREPLICAS
	READYREPLICAS=$(echo "${JSON}" | jq -r "${FILTER1}")
	read -r -d '' FILTER2 <<-'EOF'
		.status.replicas // empty
	EOF
	local REPLICAS
	REPLICAS=$(echo "${JSON}" | jq -r "${FILTER2}")
	local STATUS="${READYREPLICAS} ${REPLICAS}"

	# print X Y
	printf "%s" "${STATUS}"
}

if [[ -n ${RESOURCE} ]]; then
	ALIVE=0
	while [[ $ALIVE == 0 ]]; do
		read -r TARGET READY < <(getDeploymentReady "${RESOURCE}" "${NAMESPACE}")

		## check alive
		if [[ -n ${READY} && -n ${TARGET} ]]; then
			if [[ ${READY} -eq ${TARGET} ]]; then
				ALIVE=1
				break
			fi
		fi

		## normalise values
		if [[ -z ${READY} ]]; then
			READY="0"
		fi
		if [[ -z ${TARGET} ]]; then
			TARGET="0"
		fi
		printf "%s\n" "[ K8S/DEPLOYMENT-READY ] REPLICAS [ ${NAMESPACE}/${RESOURCE}:${READY}/${TARGET} ] waiting for RESOURCE.. sleep ${VAR_SLEEP}" 1>&2
		sleep ${VAR_SLEEP}
		ELAPSED=$((ELAPSED + VAR_SLEEP))
		if [[ ${WAIT_TIMEOUT} -gt 0 && ${ELAPSED} -ge ${WAIT_TIMEOUT} ]]; then
			printf "%s\n" "[ K8S/DEPLOYMENT-READY ] ERROR: ${NAMESPACE}/${RESOURCE} not ready after ${WAIT_TIMEOUT}s" 1>&2
			exit 1
		fi
	done
	printf "%s\n" "[ K8S/DEPLOYMENT-READY ] REPLICAS [ ${NAMESPACE}/${RESOURCE}:${READY}/${TARGET} ] is ALIVE !!" 1>&2
else
	printf "%s\n" "[ K8S/DEPLOYMENT-READY ] ERROR: No DEPLOYMENT defined" 1>&2
fi
```

Note: this version also resolves the previous `ARRSTATUS=($(...))` word-splitting (shellcheck SC2207) by reading the two values directly with `read`. The parsing behavior is unchanged. **Tab indentation is mandatory here** — the `<<-'EOF'` heredocs strip leading tabs, so the `FILTER1`/`FILTER2` bodies and their `EOF` terminators must be tab-indented. Copy the block verbatim.

- [ ] **Step 2: Lint**

Run: `shellcheck healthcheck/k8s-deployment-ready`
Expected: no output, exit 0.

- [ ] **Step 3: Syntax check**

Run: `bash -n healthcheck/k8s-deployment-ready`
Expected: no output, exit 0.

- [ ] **Step 4: Commit**

```bash
git add healthcheck/k8s-deployment-ready
git commit -m "healthcheck/k8s-deployment-ready: add optional WAIT_TIMEOUT (default unbounded)"
```

---

## Task 3: `k3s/install` — parameterised component disable

**Files:**
- Modify: `k3s/install`

- [ ] **Step 1: Replace the file**

```bash
#!/bin/bash
## module: k3s/install
## purpose: install the k3s server and place a kubeconfig at /root/.kube/config
## inputs:  K3S_DISABLE (comma list of bundled components to disable; default servicelb,traefik)
## needs:   -

## install k3s
K3S_DISABLE="${K3S_DISABLE:-servicelb,traefik}"
export INSTALL_K3S_CHANNEL_URL="https://update.k3s.io/v1-release/channels"
export INSTALL_K3S_CHANNEL="stable"
echo "### installing k3s --disable=${K3S_DISABLE} ###"
curl -fsSL https://get.k3s.io | sh -s - --disable="${K3S_DISABLE}"

## kubeconfig
echo "### sync kubeconfig ###"
while [ ! -f /etc/rancher/k3s/k3s.yaml ]; do
	echo "kubeconfig [ /etc/rancher/k3s/k3s.yaml ] not exist yet"
	sleep 3
done
echo "kubeconfig [ /etc/rancher/k3s/k3s.yaml ] exists!"
mkdir -p /root/.kube
cp /etc/rancher/k3s/k3s.yaml /root/.kube/config

## kubectl
sleep 3
kubectl get nodes
```

- [ ] **Step 2: Lint**

Run: `shellcheck k3s/install`
Expected: no output, exit 0.

- [ ] **Step 3: Syntax check**

Run: `bash -n k3s/install`
Expected: no output, exit 0.

- [ ] **Step 4: Behavioral test — the disable default is preserved**

Run: `bash -c 'K3S_DISABLE="${K3S_DISABLE:-servicelb,traefik}"; echo "$K3S_DISABLE"'`
Expected: prints `servicelb,traefik` — confirms a standalone call (no env) keeps today's behavior.

- [ ] **Step 5: Commit**

```bash
git add k3s/install
git commit -m "k3s/install: drive --disable list from K3S_DISABLE env var"
```

---

## Task 4: `k3s/prepare` — OS-aware host prep (new)

**Files:**
- Create: `k3s/prepare`

- [ ] **Step 1: Create the file**

```bash
#!/bin/bash
## module: k3s/prepare
## purpose: prepare the host OS for k3s (the only OS-specific module)
## inputs:  -
## needs:   -

## OS identity (log only)
if [[ -r /etc/os-release ]]; then
	# shellcheck disable=SC1091
	. /etc/os-release
	echo "[ K3S/PREPARE ] host [ ${PRETTY_NAME:-unknown} ]"
else
	echo "[ K3S/PREPARE ] WARNING: /etc/os-release not found — unrecognised OS" 1>&2
fi

## required commands
for bin in curl ip jq; do
	if ! command -v "${bin}" >/dev/null 2>&1; then
		echo "[ K3S/PREPARE ] ERROR: required command [ ${bin} ] not found — install it and re-run" 1>&2
		exit 1
	fi
done
echo "[ K3S/PREPARE ] selinux [ $(getenforce 2>/dev/null || echo n/a) ]"

## detect init system
if command -v systemctl >/dev/null 2>&1; then
	INIT="systemd"
elif command -v rc-update >/dev/null 2>&1; then
	INIT="openrc"
else
	INIT="unknown"
fi
echo "[ K3S/PREPARE ] init [ ${INIT} ]"

## init-system specific prep
case "${INIT}" in
	systemd)
		## Rocky / CentOS / Fedora — disable firewalld (interferes with flannel CNI)
		systemctl disable --now firewalld 2>/dev/null
		systemctl mask firewalld 2>/dev/null
		echo "[ K3S/PREPARE ] firewalld [ disabled + masked ]"
		;;
	openrc)
		## Alpine — k3s requires the cgroups service under OpenRC
		rc-update add cgroups boot 2>/dev/null
		rc-service cgroups start 2>/dev/null
		echo "[ K3S/PREPARE ] cgroups [ enabled ]"
		;;
	*)
		echo "[ K3S/PREPARE ] WARNING: unknown init system — no host prep applied" 1>&2
		;;
esac
```

- [ ] **Step 2: Make executable**

Run: `chmod +x k3s/prepare`
Expected: no output.

- [ ] **Step 3: Lint**

Run: `shellcheck k3s/prepare`
Expected: no output, exit 0. (The `SC1091` for `. /etc/os-release` is suppressed inline.)

- [ ] **Step 4: Syntax check**

Run: `bash -n k3s/prepare`
Expected: no output, exit 0.

- [ ] **Step 5: Behavioral test — required-command check works**

Run: `( PATH=/nonexistent bash k3s/prepare ); echo "exit=$?"`
Expected: prints an `ERROR: required command [ curl ]` line and `exit=1`.

- [ ] **Step 6: Commit**

```bash
git add k3s/prepare
git commit -m "k3s/prepare: add OS-aware host prep (firewalld/cgroups, sanity checks)"
```

---

## Task 5: `metallb/install` — native manifest at latest release

**Files:**
- Modify: `metallb/install`

- [ ] **Step 1: Replace the file**

```bash
#!/bin/bash
## module: metallb/install
## purpose: install MetalLB (native mode) at the latest release
## inputs:  KUBECONFIG, LABOPS_ROOT, METALLB_VERSION (optional pin override)
## needs:   healthcheck/k8s-local

## ── labops module resolver ───────────────────────────────────────────
LABOPS_BASE="${LABOPS_BASE:-https://labops.sh}"
command -v run >/dev/null 2>&1 || run() {
	local module="$1"; shift
	if [[ -n "${LABOPS_ROOT:-}" && -f "${LABOPS_ROOT}/${module}" ]]; then
		bash "${LABOPS_ROOT}/${module}" "$@"
	else
		curl -fsSL "${LABOPS_BASE}/${module}" | bash -s -- "$@"
	fi
}

## wait for the API
run healthcheck/k8s-local

## resolve the MetalLB version (latest release unless pinned via METALLB_VERSION)
METALLB_VERSION="${METALLB_VERSION:-$(curl -fsSL https://api.github.com/repos/metallb/metallb/releases/latest \
	| sed -n 's/.*"tag_name": *"\([^"]*\)".*/\1/p' | head -1)}"
if [[ -z "${METALLB_VERSION}" ]]; then
	echo "[ METALLB/INSTALL ] ERROR: could not resolve latest MetalLB release" 1>&2
	exit 1
fi
echo "[ METALLB/INSTALL ] version [ ${METALLB_VERSION} ]"

## install MetalLB — native mode (L2, no BGP)
## note: strictARP is only required for IPVS kube-proxy; k3s defaults to iptables — not applicable
kubectl apply -f "https://raw.githubusercontent.com/metallb/metallb/${METALLB_VERSION}/config/manifests/metallb-native.yaml"
```

- [ ] **Step 2: Lint**

Run: `shellcheck metallb/install`
Expected: no output, exit 0.

- [ ] **Step 3: Syntax check**

Run: `bash -n metallb/install`
Expected: no output, exit 0.

- [ ] **Step 4: Behavioral test — version resolution works**

Run: `curl -fsSL https://api.github.com/repos/metallb/metallb/releases/latest | sed -n 's/.*"tag_name": *"\([^"]*\)".*/\1/p' | head -1`
Expected: prints a version tag like `v0.16.0` (non-empty, starts with `v`).

- [ ] **Step 5: Commit**

```bash
git add metallb/install
git commit -m "metallb/install: use native manifest at latest release; dedupe wait via healthcheck/k8s-local"
```

---

## Task 6: `metallb/prepare` — IPAddressPool + L2Advertisement

**Files:**
- Modify: `metallb/prepare`

- [ ] **Step 1: Replace the file**

```bash
#!/bin/bash
## module: metallb/prepare
## purpose: configure MetalLB L2 to advertise the host IP for LoadBalancer services
## inputs:  KUBECONFIG, LABOPS_ROOT
## needs:   healthcheck/k8s-local, healthcheck/k8s-deployment-ready

## ── labops module resolver ───────────────────────────────────────────
LABOPS_BASE="${LABOPS_BASE:-https://labops.sh}"
command -v run >/dev/null 2>&1 || run() {
	local module="$1"; shift
	if [[ -n "${LABOPS_ROOT:-}" && -f "${LABOPS_ROOT}/${module}" ]]; then
		bash "${LABOPS_ROOT}/${module}" "$@"
	else
		curl -fsSL "${LABOPS_BASE}/${module}" | bash -s -- "$@"
	fi
}

## wait for the API and the MetalLB controller
run healthcheck/k8s-local
run healthcheck/k8s-deployment-ready controller metallb-system

## determine the IPv4 address of the default-route interface
ETH=$(ip route show default | awk '/default/ {print $5; exit}')
IPADDRESS=$(ip -4 addr show "${ETH}" | awk '/inet / {print $2; exit}' | cut -d/ -f1)
if [[ -z "${IPADDRESS}" ]]; then
	echo "[ METALLB/PREPARE ] ERROR: could not determine host IPv4 address" 1>&2
	exit 1
fi
echo "[ METALLB/PREPARE ] host-pool address [ ${IPADDRESS}/32 ]"

## apply the IPAddressPool + L2Advertisement (both required for L2 mode)
read -r -d '' METALCONFIG <<EOF
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: host-pool
  namespace: metallb-system
spec:
  addresses:
  - ${IPADDRESS}/32
---
apiVersion: metallb.io/v1beta1
kind: L2Advertisement
metadata:
  name: host-l2
  namespace: metallb-system
spec:
  ipAddressPools:
  - host-pool
EOF

printf '%s\n' "${METALCONFIG}"
printf '%s\n' "${METALCONFIG}" | kubectl apply -f -
```

- [ ] **Step 2: Lint**

Run: `shellcheck metallb/prepare`
Expected: no output, exit 0.

- [ ] **Step 3: Syntax check**

Run: `bash -n metallb/prepare`
Expected: no output, exit 0.

- [ ] **Step 4: Behavioral test — host IP detection works on this Fedora host**

Run:
```bash
ETH=$(ip route show default | awk '/default/ {print $5; exit}')
ip -4 addr show "$ETH" | awk '/inet / {print $2; exit}' | cut -d/ -f1
```
Expected: prints this host's primary IPv4 address (e.g. `192.168.1.250`) — confirms the `ip route` replacement for the old `route` command works without `net-tools`.

- [ ] **Step 5: Commit**

```bash
git add metallb/prepare
git commit -m "metallb/prepare: add L2Advertisement; fix host-IP detection (ip route); harden printf"
```

---

## Task 7: `storage/install` — detect-and-skip provisioner

**Files:**
- Modify: `storage/install`

- [ ] **Step 1: Replace the file**

```bash
#!/bin/bash
## module: storage/install
## purpose: ensure a local-path provisioner and a 'standard' StorageClass exist
## inputs:  KUBECONFIG, LABOPS_ROOT
## needs:   healthcheck/k8s-local

## ── labops module resolver ───────────────────────────────────────────
LABOPS_BASE="${LABOPS_BASE:-https://labops.sh}"
command -v run >/dev/null 2>&1 || run() {
	local module="$1"; shift
	if [[ -n "${LABOPS_ROOT:-}" && -f "${LABOPS_ROOT}/${module}" ]]; then
		bash "${LABOPS_ROOT}/${module}" "$@"
	else
		curl -fsSL "${LABOPS_BASE}/${module}" | bash -s -- "$@"
	fi
}

## wait for the API
run healthcheck/k8s-local

## detect an existing rancher.io/local-path provisioner (k3s bundles one)
if kubectl get storageclass -o jsonpath='{.items[*].provisioner}' 2>/dev/null \
	| tr ' ' '\n' | grep -qx 'rancher.io/local-path'; then
	echo "[ STORAGE/INSTALL ] local-path provisioner already present — skipping deploy"
else
	echo "[ STORAGE/INSTALL ] deploying rancher local-path-provisioner"
	mkdir -p /opt/local-path-provisioner
	kubectl apply -f https://raw.githubusercontent.com/rancher/local-path-provisioner/master/deploy/local-path-storage.yaml
fi

## always ensure the 'standard' StorageClass (labops apps reference it by name)
read -r -d '' LOCALSTORAGE <<EOF
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: standard
provisioner: rancher.io/local-path
reclaimPolicy: Delete
volumeBindingMode: WaitForFirstConsumer
EOF

printf '%s\n' "${LOCALSTORAGE}"
printf '%s\n' "${LOCALSTORAGE}" | kubectl apply -f -
```

- [ ] **Step 2: Lint**

Run: `shellcheck storage/install`
Expected: no output, exit 0.

- [ ] **Step 3: Syntax check**

Run: `bash -n storage/install`
Expected: no output, exit 0.

- [ ] **Step 4: Commit**

```bash
git add storage/install
git commit -m "storage/install: detect-and-skip provisioner; always ensure 'standard' StorageClass"
```

---

## Task 8: `k3s/verify` — toggle-aware health checks (new)

**Files:**
- Create: `k3s/verify`

- [ ] **Step 1: Create the file**

```bash
#!/bin/bash
## module: k3s/verify
## purpose: assert the cluster reached its intended end state
## inputs:  KUBECONFIG, K3S_STORAGE, K3S_METRICS
## needs:   -

K3S_STORAGE="${K3S_STORAGE:-on}"
K3S_METRICS="${K3S_METRICS:-on}"
FAIL=0

retry() {  ## retry <attempts> <sleep-seconds> <command...>
	local n="$1" s="$2"; shift 2
	local i
	for ((i = 1; i <= n; i++)); do
		"$@" >/dev/null 2>&1 && return 0
		sleep "${s}"
	done
	return 1
}

check() {  ## check <label> <command...>
	local label="$1"; shift
	if "$@"; then
		echo "[ K3S/VERIFY ] OK   — ${label}"
	else
		echo "[ K3S/VERIFY ] FAIL — ${label}" 1>&2
		FAIL=1
	fi
}

node_ready() {
	local out
	out="$(kubectl get nodes --no-headers 2>/dev/null)" || return 1
	[[ -n "${out}" ]] || return 1
	! echo "${out}" | awk '{print $2}' | grep -qvw 'Ready'
}

pods_ok() {
	local out
	out="$(kubectl -n kube-system get pods --no-headers 2>/dev/null)" || return 1
	[[ -n "${out}" ]] || return 1
	! echo "${out}" | awk '{print $3}' | grep -qvE '^(Running|Completed)$'
}

check "node(s) Ready"            retry 24 5 node_ready
check "kube-system pods healthy" retry 24 5 pods_ok
check "metallb controller Ready" retry 24 5 kubectl -n metallb-system rollout status deploy/controller --timeout=5s
check "metallb IPAddressPool"    retry 6  5 kubectl -n metallb-system get ipaddresspool host-pool
check "metallb L2Advertisement"  retry 6  5 kubectl -n metallb-system get l2advertisement host-l2

if [[ "${K3S_STORAGE}" == "on" ]]; then
	check "StorageClass standard" retry 6 5 kubectl get storageclass standard
fi
if [[ "${K3S_METRICS}" == "on" ]]; then
	check "metrics-server top node" retry 24 5 kubectl top node
fi

if [[ "${FAIL}" -ne 0 ]]; then
	echo "[ K3S/VERIFY ] cluster verification FAILED" 1>&2
	exit 1
fi
echo "[ K3S/VERIFY ] cluster verification PASSED"
```

- [ ] **Step 2: Make executable**

Run: `chmod +x k3s/verify`
Expected: no output.

- [ ] **Step 3: Lint**

Run: `shellcheck k3s/verify`
Expected: no output, exit 0.

- [ ] **Step 4: Syntax check**

Run: `bash -n k3s/verify`
Expected: no output, exit 0.

(Functional verification of `k3s/verify` happens in Task 13 against the real cluster.)

- [ ] **Step 5: Commit**

```bash
git add k3s/verify
git commit -m "k3s/verify: add toggle-aware cluster health assertions"
```

---

## Task 9: `k3s/up` — orchestrator (new)

**Files:**
- Create: `k3s/up`

- [ ] **Step 1: Create the file**

```bash
#!/bin/bash
## module: k3s/up
## purpose: orchestrate a full k3s host install (idempotent)
## inputs:  K3S_STORAGE, K3S_METRICS (on/off), K3S_DRYRUN (non-empty = print plan and exit)
## needs:   k3s/prepare, k3s/install, storage/install, metallb/install, metallb/prepare, k3s/verify
set -euo pipefail

## logging
exec &> >(tee -a /root/k3s-install.log)
echo "=== k3s/up — $(date -Is) ==="

## resolve + export the repo root and the module resolver
LABOPS_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LABOPS_BASE="${LABOPS_BASE:-https://labops.sh}"
export LABOPS_ROOT LABOPS_BASE
run() {
	local module="$1"; shift
	if [[ -n "${LABOPS_ROOT:-}" && -f "${LABOPS_ROOT}/${module}" ]]; then
		bash "${LABOPS_ROOT}/${module}" "$@"
	else
		curl -fsSL "${LABOPS_BASE}/${module}" | bash -s -- "$@"
	fi
}
export -f run

## cluster access + bounded waits for downstream modules
export KUBECONFIG="/root/.kube/config"
export WAIT_TIMEOUT="${WAIT_TIMEOUT:-300}"

## ── component config (override via env) ──────────────────────────────
: "${K3S_STORAGE:=on}"   # on -> k3s bundled local-path + 'standard' SC | off -> disabled
: "${K3S_METRICS:=on}"   # on -> k3s bundled metrics-server             | off -> disabled

## derive the k3s --disable list and the module sequence
DISABLE="servicelb,traefik"
MODULES=( k3s/prepare k3s/install )
[[ "${K3S_STORAGE}" == "off" ]] && DISABLE+=",local-storage"
[[ "${K3S_METRICS}" == "off" ]] && DISABLE+=",metrics-server"
MODULES+=( metallb/install metallb/prepare )
[[ "${K3S_STORAGE}" == "on" ]] && MODULES+=( storage/install )
MODULES+=( k3s/verify )

export K3S_DISABLE="${DISABLE}"
export K3S_STORAGE K3S_METRICS

echo "[ K3S/UP ] storage [ ${K3S_STORAGE} ]  metrics [ ${K3S_METRICS} ]  --disable [ ${DISABLE} ]"
echo "[ K3S/UP ] modules [ ${MODULES[*]} ]"

## dry-run: print the plan and stop before changing anything
if [[ -n "${K3S_DRYRUN:-}" ]]; then
	echo "[ K3S/UP ] dry-run — exiting before execution"
	exit 0
fi

## run the stack
for m in "${MODULES[@]}"; do
	echo ">>> ${m}"
	run "${m}"
done

echo "=== k3s/up — complete — $(date -Is) ==="
```

- [ ] **Step 2: Make executable**

Run: `chmod +x k3s/up`
Expected: no output.

- [ ] **Step 3: Lint**

Run: `shellcheck k3s/up`
Expected: no output, exit 0.

- [ ] **Step 4: Syntax check**

Run: `bash -n k3s/up`
Expected: no output, exit 0.

- [ ] **Step 5: Behavioral test — default toggle plan**

Run: `K3S_DRYRUN=1 bash k3s/up 2>&1 | grep 'K3S/UP'`
Expected: includes a line containing `--disable [ servicelb,traefik ]` and a line
`[ K3S/UP ] modules [ k3s/prepare k3s/install metallb/install metallb/prepare storage/install k3s/verify ]`.

- [ ] **Step 6: Behavioral test — storage off**

Run: `K3S_DRYRUN=1 K3S_STORAGE=off bash k3s/up 2>&1 | grep -E 'disable|modules'`
Expected: `--disable` includes `local-storage`; `modules` does **not** include `storage/install`.

- [ ] **Step 7: Behavioral test — metrics off**

Run: `K3S_DRYRUN=1 K3S_METRICS=off bash k3s/up 2>&1 | grep -E 'disable|modules'`
Expected: `--disable` includes `metrics-server`; `modules` still includes `storage/install`.

- [ ] **Step 8: Commit**

```bash
git add k3s/up
git commit -m "k3s/up: add toggle-driven orchestrator with declarative module list"
```

---

## Task 10: `k3s/remove` — full teardown

**Files:**
- Modify: `k3s/remove`

- [ ] **Step 1: Replace the file**

```bash
#!/bin/bash
## module: k3s/remove
## purpose: tear down k3s and reset the host for a clean reinstall
## inputs:  $1=--purge (optional — also delete local-path PV data)
## needs:   -

PURGE="no"
[[ "${1:-}" == "--purge" ]] && PURGE="yes"

## uninstall k3s
if [[ -x /usr/local/bin/k3s-uninstall.sh ]]; then
	echo "[ K3S/REMOVE ] running k3s-uninstall.sh"
	/usr/local/bin/k3s-uninstall.sh
else
	echo "[ K3S/REMOVE ] k3s-uninstall.sh not found — k3s not installed"
fi

## remove the kubeconfig
rm -f /root/.kube/config
echo "[ K3S/REMOVE ] removed /root/.kube/config"

## local-path PV data
if [[ -d /opt/local-path-provisioner ]]; then
	if [[ "${PURGE}" == "yes" ]]; then
		rm -rf /opt/local-path-provisioner
		echo "[ K3S/REMOVE ] purged /opt/local-path-provisioner"
	else
		echo "[ K3S/REMOVE ] kept PV data at /opt/local-path-provisioner (pass --purge to delete)"
	fi
fi
```

- [ ] **Step 2: Lint**

Run: `shellcheck k3s/remove`
Expected: no output, exit 0.

- [ ] **Step 3: Syntax check**

Run: `bash -n k3s/remove`
Expected: no output, exit 0.

- [ ] **Step 4: Commit**

```bash
git add k3s/remove
git commit -m "k3s/remove: upgrade to full teardown with opt-in --purge for PV data"
```

---

## Task 11: `k3s/runonce.sh` — VM-boot shim

**Files:**
- Modify: `k3s/runonce.sh`

- [ ] **Step 1: Replace the file**

```bash
#!/bin/bash
## module: k3s/runonce.sh
## purpose: VM first-boot shim — run the k3s host stack, then signal completion
## inputs:  -
## needs:   k3s/up

LABOPS_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
if [[ -f "${LABOPS_ROOT}/k3s/up" ]]; then
	bash "${LABOPS_ROOT}/k3s/up"
else
	curl -fsSL "${LABOPS_BASE:-https://labops.sh}/k3s/up" | bash
fi

## VM-stage completion sentinel (detailed log is /root/k3s-install.log)
echo "1" > /root/startup.done
exit 0
```

- [ ] **Step 2: Lint**

Run: `shellcheck k3s/runonce.sh`
Expected: no output, exit 0.

- [ ] **Step 3: Syntax check**

Run: `bash -n k3s/runonce.sh`
Expected: no output, exit 0.

- [ ] **Step 4: Commit**

```bash
git add k3s/runonce.sh
git commit -m "k3s/runonce.sh: thin to a VM-boot shim that delegates to k3s/up"
```

---

## Task 12: `k3s/README.md` — usage doc (new)

**Files:**
- Create: `k3s/README.md`

- [ ] **Step 1: Create the file**

```markdown
# k3s — single-node host install

Installs a usable single-node k3s cluster on a persistent host:
**k3s + MetalLB + local-path storage + metrics-server**.

## Usage

From a clone of this repo, on the target host:

```
sudo ./k3s/up
```

This runs, in order: host prep → k3s → MetalLB → storage → verification.
It is idempotent — safe to re-run. The detailed log is `/root/k3s-install.log`.

### Component toggles (env vars)

| Var | Default | Off behaviour |
|-----|---------|---------------|
| `K3S_STORAGE` | `on` | k3s `--disable=local-storage` — bring your own (e.g. Longhorn) |
| `K3S_METRICS` | `on` | k3s `--disable=metrics-server` |

Example: `sudo K3S_STORAGE=off ./k3s/up`

Use `K3S_DRYRUN=1 ./k3s/up` to print the resolved plan without changing anything.

## Teardown

```
sudo ./k3s/remove            # removes k3s + kubeconfig, keeps PV data
sudo ./k3s/remove --purge    # also deletes /opt/local-path-provisioner
```

## Verify anytime

```
sudo KUBECONFIG=/root/.kube/config ./k3s/verify
```

## Prerequisites

- `curl`, `ip` (iproute), and `jq` must be installed on the host.
- Supported hosts: systemd (Rocky / CentOS / Fedora) and OpenRC (Alpine).
  On Alpine the `bash` package must be installed.
```

- [ ] **Step 2: Commit**

```bash
git add k3s/README.md
git commit -m "k3s/README.md: document the host install, toggles, and teardown"
```

---

## Task 13: Acceptance — install on the NUC

**This task modifies the host.** It performs the actual k3s install. Commands
assume the executor runs as `root` (the README shows the `sudo` form for non-root users).

- [ ] **Step 1: Run the orchestrator**

Run: `/root/labops/k3s/up`
Expected: completes without error; the final lines include `[ K3S/VERIFY ] cluster verification PASSED` and `=== k3s/up — complete`.

- [ ] **Step 2: Confirm the node and components**

Run: `kubectl get nodes,sc,pods -A`
Expected: one node `Ready`; StorageClasses include both `local-path` and `standard`; pods in `kube-system` and `metallb-system` are `Running`.

- [ ] **Step 3: Confirm MetalLB L2 config exists**

Run: `kubectl -n metallb-system get ipaddresspool,l2advertisement`
Expected: `ipaddresspool/host-pool` and `l2advertisement/host-l2` are listed.

- [ ] **Step 4: Functional check — a LoadBalancer service gets the host IP**

Run:
```bash
kubectl create deploy lbtest --image=nginx --port=80
kubectl expose deploy lbtest --type=LoadBalancer --port=80
bash /root/labops/healthcheck/k8s-external-ip lbtest default
```
Expected: `k8s-external-ip` prints `[ K8S/EXTERNAL-IP ] ... is ALIVE !!` with the host IP and port `80` — confirming MetalLB allocates and advertises the host IP (the `L2Advertisement` fix working end to end).

- [ ] **Step 5: Clean up the functional check**

Run: `kubectl delete deploy/lbtest svc/lbtest`
Expected: both deleted.

(No commit — this task changes the host, not the repo.)

---

## Task 14: Acceptance — idempotency

- [ ] **Step 1: Re-run the orchestrator on the already-installed host**

Run: `/root/labops/k3s/up`
Expected: completes without error and ends with `cluster verification PASSED`. `metallb/install` reports the same version; `storage/install` prints `local-path provisioner already present — skipping deploy`.

- [ ] **Step 2: Confirm no duplicate/abnormal state**

Run: `kubectl get sc`
Expected: still exactly one `standard` and one `local-path` StorageClass (no duplicates).

---

## Task 15: Acceptance — teardown and rebuild

- [ ] **Step 1: Tear down (keep PV data)**

Run: `/root/labops/k3s/remove`
Expected: runs `k3s-uninstall.sh`, removes `/root/.kube/config`, prints `kept PV data at /opt/local-path-provisioner`.

- [ ] **Step 2: Confirm k3s is gone**

Run: `command -v k3s; ls /usr/local/bin/k3s-uninstall.sh 2>&1`
Expected: `k3s` not found; uninstall script no longer present.

- [ ] **Step 3: Rebuild**

Run: `/root/labops/k3s/up`
Expected: completes cleanly, ending with `cluster verification PASSED` — confirms a teardown→rebuild cycle works and leaves the host in the desired final state.

---

## Done

After Task 15 the NUC runs a verified k3s cluster (k3s + MetalLB + bundled storage/metrics), the automation is idempotent and re-runnable, and all script changes are committed to `master`.
