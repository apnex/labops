# GitOps Service Registry — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. (This plan's chosen execution mode is **inline** — `superpowers:executing-plans`.)

**Goal:** Add a single curated registry file (`argo/services.yaml`) that bootstraps services from remote public repos into k3s via an Argo CD `ApplicationSet`, and remediate the `argo/` install scripts it depends on.

**Architecture:** A top-level YAML list (`argo/services.yaml`) is read by an Argo CD `ApplicationSet` Git file generator, which templates one `Application` per entry (`goTemplate` branches on `git` vs `helm`). The retired `app.index.yaml` app-of-apps is removed; nothing auto-loads. The `argo/` lifecycle scripts (`install`, `set-service`, `cli-install`, `set-password`, `remove`) are corrected per the spec audit.

**Tech Stack:** Argo CD + `ApplicationSet`, `kubectl`, bash, `shellcheck`.

**Reference spec:** `docs/superpowers/specs/2026-05-22-gitops-service-registry-design.md`

---

## Conventions

- **Target:** the `labops` repo at `/root/labops`; the live k3s cluster on this NUC (from the earlier k3s work). Tasks 1–8 edit/commit repo files; Tasks 9–10 modify the cluster.
- **Indentation:** shell scripts use **TAB** indentation; YAML files use **space** indentation.
- **shellcheck gate:** every edited shell script must be `shellcheck`-clean (no output).
- **Commit footer:** every commit message ends with:
  `Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>`
- Commits go directly to `master` (consistent with this repo and the earlier work).
- **Host-modifying:** Tasks 9–10 install Argo CD on the NUC and deploy workloads — pause for a checkpoint before them.

---

## Task 1: `argo/install` — remediate + retire `app.index.yaml`

**Files:**
- Modify: `argo/install`
- Remove: `argo/app.index.yaml`

- [ ] **Step 1: Replace `argo/install`** with EXACTLY:

```bash
#!/bin/bash
## module: argo/install
## purpose: install Argo CD and the labops service-registry ApplicationSet
## inputs:  KUBECONFIG
## needs:   -
# https://argo-cd.readthedocs.io/en/stable/getting_started/

## namespace (idempotent)
kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -

## install Argo CD (stable channel)
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

## wait for the ApplicationSet CRD to register before applying our ApplicationSet
kubectl wait --for=condition=established --timeout=60s crd/applicationsets.argoproj.io

## apply the labops service-registry ApplicationSet (created in Task 7)
kubectl apply -n argocd -f https://labops.sh/argo/services.appset.yaml
```

- [ ] **Step 2: Remove the retired auto-loader**

Run: `git rm -q argo/app.index.yaml`
Expected: `argo/app.index.yaml` staged for deletion.

- [ ] **Step 3: Lint**

Run: `shellcheck argo/install`
Expected: no output, exit 0.

- [ ] **Step 4: Syntax check**

Run: `bash -n argo/install`
Expected: no output, exit 0.

- [ ] **Step 5: Commit**

```bash
git add argo/install argo/app.index.yaml
git commit -m "argo/install: idempotent namespace; apply services.appset.yaml; retire app.index.yaml"
```

---

## Task 2: `argo/set-service` — stop deleting `argocd-server`

**Files:**
- Modify: `argo/set-service`

- [ ] **Step 1: Replace `argo/set-service`** with EXACTLY:

```bash
#!/bin/bash
## module: argo/set-service
## purpose: expose the Argo CD UI as a LoadBalancer (vip-argocd-server)
## inputs:  KUBECONFIG
## needs:   -

## expose the Argo CD UI as a LoadBalancer (vip-argocd-server), alongside argocd-server
kubectl -n argocd apply -f https://labops.sh/argo/argo.vip.yaml
```

(Removes the `kubectl delete services argocd-server` line — needless and risky; `vip-argocd-server` is a separate service — and drops the dead commented-out patch block.)

- [ ] **Step 2: Lint**

Run: `shellcheck argo/set-service`
Expected: no output, exit 0.

- [ ] **Step 3: Syntax check**

Run: `bash -n argo/set-service`
Expected: no output, exit 0.

- [ ] **Step 4: Commit**

```bash
git add argo/set-service
git commit -m "argo/set-service: add the LoadBalancer alongside argocd-server, do not delete it"
```

---

## Task 3: `argo/cli-install` — remediate + module header + `run` resolver

**Files:**
- Modify: `argo/cli-install`

- [ ] **Step 1: Replace `argo/cli-install`** with EXACTLY this content (the resolver function body is TAB-indented):

```bash
#!/bin/bash
## module: argo/cli-install
## purpose: install the argocd CLI from the running Argo CD server
## inputs:  KUBECONFIG, LABOPS_ROOT (auto-detected if unset)
## needs:   healthcheck/k8s-external-ip, healthcheck/net-ssl

## ── labops module resolver ───────────────────────────────────────────
LABOPS_BASE="${LABOPS_BASE:-https://labops.sh}"
LABOPS_ROOT="${LABOPS_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
command -v run >/dev/null 2>&1 || run() {
	local module="$1"; shift
	if [[ -n "${LABOPS_ROOT:-}" && -f "${LABOPS_ROOT}/${module}" ]]; then
		bash "${LABOPS_ROOT}/${module}" "$@"
	else
		curl -fsSL "${LABOPS_BASE}/${module}" | bash -s -- "$@"
	fi
}

## healthcheck: wait for the vip-argocd-server external IP
ARGOCD_SERVER=$(run healthcheck/k8s-external-ip vip-argocd-server argocd)

## healthcheck: wait for the server TLS to be ready
run healthcheck/net-ssl "${ARGOCD_SERVER}"

## fetch the argocd CLI from the server
curl -ksLo /usr/local/bin/argocd "https://${ARGOCD_SERVER}/download/argocd-linux-amd64"
chmod +x /usr/local/bin/argocd

## verify
argocd login --core
argocd version --insecure
```

Changes from the original: the `2>/dev/tty` redirects are gone (they break in non-interactive runs — no controlling terminal); the dead `ARGOCD_THUMBPRINT` capture is gone; the CLI installs to `/usr/local/bin` (was `/usr/bin`); the module header is added; and the two healthcheck calls now go through the inlined `run` resolver with positional args (both `healthcheck/k8s-external-ip` and `healthcheck/net-ssl` accept `$1`/`$2`) instead of the bare `curl … | bash` pattern.

- [ ] **Step 2: Lint**

Run: `shellcheck argo/cli-install`
Expected: no output, exit 0.

- [ ] **Step 3: Syntax check**

Run: `bash -n argo/cli-install`
Expected: no output, exit 0.

- [ ] **Step 4: Verify tab indentation**

Run: `grep -nP '^ +\S' argo/cli-install`
Expected: no output (the resolver function body is tab-indented).

- [ ] **Step 5: Commit**

```bash
git add argo/cli-install
git commit -m "argo/cli-install: remediate; add module header and run resolver"
```

---

## Task 4: `argo/set-password` — add `admin.passwordMtime`

**Files:**
- Modify: `argo/set-password`

- [ ] **Step 1: Replace `argo/set-password`** with EXACTLY this content (the `if` body and the JSON lines are TAB-indented):

```bash
#!/bin/bash
## module: argo/set-password
## purpose: set the Argo CD admin password
## inputs:  $1 = password (default VMware1!), KUBECONFIG
## needs:   -

NEWPASSWORD="${1}"   ## password from arg 1
if [[ -z ${NEWPASSWORD} ]]; then
	NEWPASSWORD="VMware1!"   ## default password
fi

## bcrypt the new password
NEWSECRET=$(argocd account bcrypt --password "${NEWPASSWORD}")
echo "Reset admin password to [ ${NEWPASSWORD} ]"

## patch argocd-secret — admin.password + admin.passwordMtime (Argo registers the change)
NOW=$(date -u +%Y-%m-%dT%H:%M:%SZ)
kubectl patch secret -n argocd argocd-secret -p '{
	"stringData": {
		"admin.password": "'"${NEWSECRET}"'",
		"admin.passwordMtime": "'"${NOW}"'"
	}
}'
```

The added `admin.passwordMtime` (RFC3339 UTC) is what Argo CD uses to register the password change and invalidate stale tokens — Argo's documented reset patches both fields.

- [ ] **Step 2: Lint**

Run: `shellcheck argo/set-password`
Expected: no output, exit 0.

- [ ] **Step 3: Syntax check**

Run: `bash -n argo/set-password`
Expected: no output, exit 0.

- [ ] **Step 4: Verify tab indentation**

Run: `grep -nP '^ +\S' argo/set-password`
Expected: no output (all indentation is tabs).

- [ ] **Step 5: Commit**

```bash
git add argo/set-password
git commit -m "argo/set-password: also set admin.passwordMtime so Argo registers the change"
```

---

## Task 5: `argo/remove` — retarget to the `services` ApplicationSet

**Files:**
- Modify: `argo/remove`

- [ ] **Step 1: Replace `argo/remove`** with EXACTLY this content (loop/`if` bodies are TAB-indented):

```bash
#!/bin/bash
## module: argo/remove
## purpose: tear down Argo CD and the service-registry ApplicationSet
## inputs:  KUBECONFIG
## needs:   -

## delete the service-registry ApplicationSet (cascades to its generated Applications)
kubectl -n argocd delete applicationset services --ignore-not-found

## clear finalizers and remove any remaining apps (stuck-app safety net)
mapfile -t APPLIST < <(kubectl -n argocd get applications -o json 2>/dev/null | jq -c '.items[]')
for APP in "${APPLIST[@]}"; do
	NAME=$(echo "${APP}" | jq -r '.metadata.name')
	echo "removing app [ ${NAME} ]"
	echo "${APP}" | jq '.metadata.finalizers = []' | kubectl replace -f -
	kubectl -n argocd delete app "${NAME}" --ignore-not-found
done

## delete the namespace
kubectl delete ns argocd --ignore-not-found

## remove the argocd CLI
CMDPATH=$(command -v argocd)
if [[ -n ${CMDPATH} ]]; then
	echo "removing [ ${CMDPATH} ]"
	rm -f "${CMDPATH}"
fi
```

Changes: deletes the `services` `ApplicationSet` (not the retired `index` app); the app loop uses `mapfile` (shellcheck-clean) and is a stuck-app safety net; `--ignore-not-found` everywhere for idempotency.

- [ ] **Step 2: Lint**

Run: `shellcheck argo/remove`
Expected: no output, exit 0.

- [ ] **Step 3: Syntax check**

Run: `bash -n argo/remove`
Expected: no output, exit 0.

- [ ] **Step 4: Verify tab indentation**

Run: `grep -nP '^ +\S' argo/remove`
Expected: no output.

- [ ] **Step 5: Commit**

```bash
git add argo/remove
git commit -m "argo/remove: delete the services ApplicationSet; mapfile loop; --ignore-not-found"
```

---

## Task 6: `argo/services.yaml` — the registry (new)

**Files:**
- Create: `argo/services.yaml`

- [ ] **Step 1: Create `argo/services.yaml`** with EXACTLY this content (YAML — space-indented), seeded with one known-good `git` entry for the acceptance:

```yaml
# labops service registry — each entry deploys one service into the cluster.
# Add an entry, commit + push — the Argo CD 'services' ApplicationSet deploys it.
# Schema + design: docs/superpowers/specs/2026-05-22-gitops-service-registry-design.md
#
# Required (all):  name, type (git|helm), repoURL, revision, namespace
# Required (git):  path        Required (helm): chart        Optional (helm): values

- name: podinfo
  type: git
  repoURL: https://github.com/stefanprodan/podinfo
  path: kustomize
  revision: master
  namespace: podinfo
```

- [ ] **Step 2: Validate YAML**

Run: `python3 -c "import yaml,sys; d=yaml.safe_load(open('argo/services.yaml')); assert isinstance(d,list) and d[0]['name']=='podinfo'; print('ok, entries:', len(d))"`
Expected: `ok, entries: 1`.

- [ ] **Step 3: Commit**

```bash
git add argo/services.yaml
git commit -m "argo/services.yaml: add the GitOps service registry (seeded with podinfo)"
```

---

## Task 7: `argo/services.appset.yaml` — the ApplicationSet (new)

**Files:**
- Create: `argo/services.appset.yaml`

- [ ] **Step 1: Create `argo/services.appset.yaml`** with EXACTLY this content:

```yaml
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: services
  namespace: argocd
spec:
  goTemplate: true
  generators:
    - git:
        repoURL: https://github.com/apnex/labops
        revision: HEAD
        files:
          - path: argo/services.yaml
  template:
    metadata:
      name: '{{ .name }}'
    spec:
      project: default
      destination:
        server: https://kubernetes.default.svc
        namespace: '{{ .namespace }}'
      source:
        repoURL: '{{ .repoURL }}'
        targetRevision: '{{ .revision }}'
        {{- if eq .type "helm" }}
        chart: '{{ .chart }}'
        {{- if .values }}
        helm:
          valuesObject:
            {{- toYaml .values | nindent 12 }}
        {{- end }}
        {{- else }}
        path: '{{ .path }}'
        {{- end }}
      syncPolicy:
        automated:
          selfHeal: true
          prune: true
        syncOptions:
          - CreateNamespace=true
        retry:
          limit: 5
          backoff:
            duration: 30s
            factor: 2
            maxDuration: 10m
```

The Git file generator reads `argo/services.yaml`; because it is a top-level list, it yields one element per entry. `goTemplate` branches the `source` on `type`. The conditional `helm` / `values` rendering is validated by `kubectl --dry-run` (Step 2) and proven live in Task 10.

- [ ] **Step 2: Validate the manifest is well-formed YAML**

Run: `python3 -c "import yaml; list(yaml.safe_load_all(open('argo/services.appset.yaml'))); print('yaml ok')"`
Expected: `yaml ok`. (Server-side schema + template rendering are validated against the live Argo CD in Task 10.)

- [ ] **Step 3: Commit**

```bash
git add argo/services.appset.yaml
git commit -m "argo/services.appset.yaml: add the registry-driven ApplicationSet"
```

---

## Task 8: Push to origin

The Argo CD install fetches `services.appset.yaml` via `labops.sh`, and the ApplicationSet's Git generator reads `argo/services.yaml` from GitHub — so the repo files must be on `origin` before the acceptance.

- [ ] **Step 1: Push**

Run: `git push origin master`
Expected: the Task 1–7 commits land on `origin/master`; `git rev-list --count @{u}..HEAD` then prints `0`.

---

## Task 9: Acceptance — install Argo CD on the NUC

**This task modifies the cluster.** It installs Argo CD onto the live k3s cluster. Runs as `root`.

- [ ] **Step 1: Install Argo CD**

Run: `/root/labops/argo/install`
Expected: namespace `argocd` applied; Argo CD manifests applied; the `services` ApplicationSet applied (`applicationset.argoproj.io/services created`).

- [ ] **Step 2: Wait for Argo CD to be ready**

Run: `kubectl -n argocd rollout status deploy/argocd-server --timeout=300s`
Expected: `deployment "argocd-server" successfully rolled out`.

- [ ] **Step 3: Expose the UI**

Run: `/root/labops/argo/set-service`
Expected: `service/vip-argocd-server created`. Then `kubectl -n argocd get svc vip-argocd-server` shows an `EXTERNAL-IP` of `192.168.1.250`.

- [ ] **Step 4: Install the CLI**

Run: `/root/labops/argo/cli-install`
Expected: the healthchecks pass, `/usr/local/bin/argocd` is installed, `argocd version` prints client + server versions.

- [ ] **Step 5: Set the admin password**

Run: `/root/labops/argo/set-password`
Expected: prints `Reset admin password to [ VMware1! ]`; `kubectl -n argocd patch secret argocd-secret` reports the secret patched.

- [ ] **Step 6: Confirm Argo CD is healthy**

Run: `kubectl -n argocd get pods`
Expected: all Argo CD pods (`argocd-server`, `argocd-repo-server`, `argocd-application-controller`, `argocd-applicationset-controller`, `argocd-redis`, `argocd-dex-server`) `Running`.

(No commit — this task changes the cluster, not the repo.)

---

## Task 10: Acceptance — registry deploy / helm / prune

**This task modifies the cluster and the repo.** It proves the registry end-to-end.

- [ ] **Step 1: Confirm the ApplicationSet generated the seeded service**

Run: `kubectl -n argocd get applicationset services && kubectl -n argocd get applications`
Expected: `applicationset/services` exists; an `Application` named `podinfo` is listed.

- [ ] **Step 2: Confirm `podinfo` synced (git source works)**

Run: `kubectl -n argocd get app podinfo -o jsonpath='{.status.sync.status} {.status.health.status}{"\n"}'` then `kubectl -n podinfo get pods`
Expected: `Synced Healthy`; podinfo pod(s) `Running` in namespace `podinfo`. (Allow a minute for first sync; re-run if `Progressing`.)

- [ ] **Step 3: Add a `helm` entry (helm source works)**

Resolve a current podinfo chart version, then append a helm entry to `argo/services.yaml`:
```bash
VER=$(curl -fsSL https://stefanprodan.github.io/podinfo/index.yaml | sed -n 's/^[[:space:]]*version:[[:space:]]*//p' | head -1)
echo "podinfo chart version: ${VER}"
cat >> argo/services.yaml <<EOF

- name: podinfo-helm
  type: helm
  repoURL: https://stefanprodan.github.io/podinfo
  chart: podinfo
  revision: ${VER}
  namespace: podinfo-helm
EOF
git add argo/services.yaml && git commit -m "services: add podinfo-helm (acceptance — helm source)" && git push origin master
```
Expected: the entry is appended; commit + push succeed.

- [ ] **Step 4: Confirm the helm service deploys**

Wait for the ApplicationSet Git generator to re-read (≈3 min poll), then:
Run: `kubectl -n argocd get app podinfo-helm -o jsonpath='{.status.sync.status} {.status.health.status}{"\n"}'` and `kubectl -n podinfo-helm get pods`
Expected: `Synced Healthy`; pods `Running` in `podinfo-helm` — confirms the `goTemplate` helm branch.

- [ ] **Step 5: Remove the helm entry (prune works)**

```bash
git revert --no-edit HEAD          # reverts the Step 3 commit
git push origin master
```
Wait ≈3 min, then run: `kubectl -n argocd get applications`
Expected: `podinfo-helm` `Application` is gone (pruned); `podinfo` remains.

- [ ] **Step 6: Confirm final state**

Run: `kubectl -n argocd get applicationset,applications && kubectl get ns podinfo`
Expected: `applicationset/services` present; `Application` `podinfo` present and `Synced/Healthy`; namespace `podinfo` exists. The registry is live and curated.

(No commit beyond the Step 3 / Step 5 registry changes.)

---

## Done

After Task 10: Argo CD runs on the NUC; `argo/services.yaml` is the single curated registry; adding a service is one list entry + commit + push; the `argo/` install scripts are corrected and shellcheck-clean; the retired `app.index.yaml` is gone. All repo changes are on `master` / `origin`.
