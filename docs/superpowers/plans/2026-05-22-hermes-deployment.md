# Hermes Agent Deployment Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Deploy a GitOps-managed, persistent Hermes agent on the NUC k3s cluster — a new public `apnex/hermes` repo holding generic deployment manifests, plus a local MetalLB LoadBalancer overlay in `labops`, both wired into the existing `services` Argo CD ApplicationSet.

**Architecture:** Two-repo split — `apnex/hermes` holds operator-agnostic manifests (`Deployment` + `ClusterIP Service` + `PVC` + `ConfigMap` template) and a `set-secret` env-reading script; `labops/hermes-vip/` holds the cluster-specific MetalLB `LoadBalancer` overlay. Both are registered in `labops/argo/services.yaml` (`hermes`, `hermes-vip`). All operator-supplied values live in the out-of-band `hermes-secrets` Secret created by `set-secret`.

**Tech Stack:** Kubernetes manifests (YAML), Argo CD, MetalLB, bash, `shellcheck`, `gh` CLI.

**Reference spec:** `docs/superpowers/specs/2026-05-22-hermes-deployment-design.md`

---

## Conventions

- **Two repos:**
  - `apnex/hermes` — *new*, default branch `main`.
  - `apnex/labops` — *existing*, branch `master`.
- Working directories: `/root/hermes` (created by Task 1), `/root/labops`.
- Shell scripts use **TAB** indentation (consistent with labops) and must be `shellcheck`-clean.
- YAML files use **space** indentation (2 spaces).
- Commits go directly to the default branch (no PRs).
- **No AI attribution** in commit messages — no `Co-Authored-By` trailer, no "Generated with…" footers, no model name references; the rule applies in the new `apnex/hermes` repo too.
- Tasks **12–14 are host-modifying** — they apply Secrets and verify the live cluster.

---

## Task 1: Create the `apnex/hermes` GitHub repo

**Files:**
- Create: `/root/hermes/` (new local clone of `apnex/hermes`).

- [ ] **Step 1: Create the public repo via `gh` and clone it locally.**

Run:
```bash
cd /root && gh repo create apnex/hermes --public \
  --description "GitOps-deployed Hermes agent for Kubernetes — generic public template" \
  --clone
```
Expected: "✓ Created repository apnex/hermes on GitHub" + "Cloning into 'hermes'…".

- [ ] **Step 2: Ensure local branch is `main` and verify remote.**

Run:
```bash
cd /root/hermes && git checkout -B main && git remote -v
```
Expected: switched to / created branch `main`; remote `origin  https://github.com/apnex/hermes  (fetch/push)`.

- [ ] **Step 3: Initial empty commit and set upstream.**

Run:
```bash
cd /root/hermes && git commit --allow-empty -m "Initial commit" && git push -u origin main
```
Expected: an empty commit lands on `origin/main`; `git rev-list --count origin/main..HEAD` → `0`.

---

## Task 2: README

**Files:**
- Create: `/root/hermes/README.md`

- [ ] **Step 1: Write `README.md`.**

````markdown
# hermes

GitOps-deployed [Hermes agent](https://github.com/NousResearch/hermes-agent) for
Kubernetes. Generic, reusable; **no operator-specific values are committed.**

## What this deploys

- `Deployment` running `nousresearch/hermes-agent` in service mode (`hermes gateway run`).
- `PersistentVolumeClaim` for `/opt/data` (Hermes's skills, sessions, memory).
- `ConfigMap` holding a `config.yaml` *template* (substituted at first boot by an init container).
- `ClusterIP` `Service` exposing `:8642` (OpenAI-compatible API) + `:9119` (web dashboard).

All operator-supplied values (LiteLLM base URL, model name, API key, API server key) live
in a Kubernetes `Secret` (`hermes-secrets`) created out-of-band by `./set-secret` — they
are never committed.

## Prerequisites

- A Kubernetes cluster with `kubectl` access.
- An OpenAI-compatible LLM endpoint (e.g. a LiteLLM router) — base URL, model ID, API key.
- A GitOps tool (point Argo CD at `manifests/`).

## Deploy

1. **Create the Secret.** Export four env vars and run `./set-secret`:

   ```sh
   export LITELLM_BASE_URL="https://your-litellm-router/v1"
   export LITELLM_MODEL="your-default-model-id"
   export LITELLM_API_KEY="your-router-api-key"
   export API_SERVER_KEY="$(openssl rand -hex 32)"   # bearer token for :8642
   ./set-secret
   ```

   Creates the `hermes` namespace if absent, then applies the `hermes-secrets` Secret.

2. **Point your GitOps tool at `manifests/`.** Argo CD example:

   ```yaml
   apiVersion: argoproj.io/v1alpha1
   kind: Application
   metadata: { name: hermes, namespace: argocd }
   spec:
     project: default
     source:
       repoURL: https://github.com/apnex/hermes
       targetRevision: main
       path: manifests
     destination: { server: https://kubernetes.default.svc, namespace: hermes }
     syncPolicy:
       automated: { selfHeal: true, prune: true }
       syncOptions: [CreateNamespace=true]
   ```

3. **Verify.** `kubectl -n hermes get pods` shows `hermes-…` Running.
   `curl -H "Authorization: Bearer ${API_SERVER_KEY}" http://<svc>:8642/v1/models` returns
   the models the LiteLLM router exposes.

## Exposure

The repo ships a `ClusterIP` Service — portable, works on any cluster. To expose Hermes
externally, add your own `Ingress`, `NodePort`, `kubectl port-forward`, or LoadBalancer
overlay on top — don't fork, overlay.

## Configuration after first boot

Hermes **owns** `/opt/data/config.yaml` once seeded and may mutate it at runtime.
Re-running with a changed template / changed `LITELLM_*` env vars **does not** update the
live file. To change config on a running instance: `kubectl exec` in and use
`hermes config set`, or recreate the PVC.
````

- [ ] **Step 2: Commit.**

```bash
cd /root/hermes && git add README.md && git commit -m "Add README"
```

---

## Task 3: `set-secret` script

**Files:**
- Create: `/root/hermes/set-secret`

- [ ] **Step 1: Write `set-secret`** (TAB-indented; values come from env vars):

```bash
#!/bin/bash
## set-secret — apply the hermes-secrets Secret to the cluster from env vars.
## Required env: LITELLM_BASE_URL, LITELLM_MODEL, LITELLM_API_KEY, API_SERVER_KEY
## Optional env: NAMESPACE (default: hermes)
set -e

NAMESPACE="${NAMESPACE:-hermes}"

for v in LITELLM_BASE_URL LITELLM_MODEL LITELLM_API_KEY API_SERVER_KEY; do
	if [[ -z "${!v}" ]]; then
		echo "Error: \$${v} is not set" >&2
		exit 1
	fi
done

## namespace (idempotent)
kubectl create namespace "${NAMESPACE}" --dry-run=client -o yaml | kubectl apply -f -

## Secret (idempotent)
kubectl create secret generic hermes-secrets -n "${NAMESPACE}" \
	--from-literal=LITELLM_BASE_URL="${LITELLM_BASE_URL}" \
	--from-literal=LITELLM_MODEL="${LITELLM_MODEL}" \
	--from-literal=LITELLM_API_KEY="${LITELLM_API_KEY}" \
	--from-literal=API_SERVER_KEY="${API_SERVER_KEY}" \
	--dry-run=client -o yaml | kubectl apply -f -

echo "hermes-secrets applied to namespace ${NAMESPACE}"
```

- [ ] **Step 2: Make executable.**

Run: `chmod +x /root/hermes/set-secret`

- [ ] **Step 3: Lint with shellcheck.**

Run: `shellcheck /root/hermes/set-secret`
Expected: no output, exit 0.

- [ ] **Step 4: Syntax check.**

Run: `bash -n /root/hermes/set-secret`
Expected: no output, exit 0.

- [ ] **Step 5: Verify tab indentation.**

Run: `grep -nP '^ +\S' /root/hermes/set-secret`
Expected: no output.

- [ ] **Step 6: Commit.**

```bash
cd /root/hermes && git add set-secret && git commit -m "Add set-secret: env-sourced Secret creation"
```

---

## Task 4: `manifests/pvc.yaml`

**Files:**
- Create: `/root/hermes/manifests/pvc.yaml`

- [ ] **Step 1: Write `manifests/pvc.yaml`.**

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: hermes-data
  namespace: hermes
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: local-path
  resources:
    requests:
      storage: 10Gi
```

- [ ] **Step 2: Validate YAML.**

Run: `python3 -c "import yaml; d=yaml.safe_load(open('/root/hermes/manifests/pvc.yaml')); assert d['kind']=='PersistentVolumeClaim' and d['spec']['resources']['requests']['storage']=='10Gi'; print('ok')"`
Expected: `ok`.

- [ ] **Step 3: Commit.**

```bash
cd /root/hermes && git add manifests/pvc.yaml && git commit -m "Add PVC for Hermes data"
```

---

## Task 5: `manifests/configmap.yaml`

**Files:**
- Create: `/root/hermes/manifests/configmap.yaml`

- [ ] **Step 1: Write `manifests/configmap.yaml`** — ConfigMap with `config.yaml.tpl`:

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: hermes-config
  namespace: hermes
data:
  config.yaml.tpl: |
    model:
      provider: custom
      base_url: @LITELLM_BASE_URL@
      default: @LITELLM_MODEL@
      key_env: LITELLM_API_KEY
```

- [ ] **Step 2: Validate YAML.**

Run: `python3 -c "import yaml; d=yaml.safe_load(open('/root/hermes/manifests/configmap.yaml')); assert d['kind']=='ConfigMap' and 'config.yaml.tpl' in d['data'] and '@LITELLM_BASE_URL@' in d['data']['config.yaml.tpl']; print('ok')"`
Expected: `ok`.

- [ ] **Step 3: Commit.**

```bash
cd /root/hermes && git add manifests/configmap.yaml && git commit -m "Add ConfigMap with config.yaml template"
```

---

## Task 6: `manifests/deployment.yaml`

**Files:**
- Create: `/root/hermes/manifests/deployment.yaml`

- [ ] **Step 1: Write `manifests/deployment.yaml`** — Deployment with init container (seed-if-absent + `sed` substitution) + main container:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: hermes
  namespace: hermes
  labels:
    app: hermes
spec:
  replicas: 1
  strategy:
    type: Recreate
  selector:
    matchLabels:
      app: hermes
  template:
    metadata:
      labels:
        app: hermes
    spec:
      initContainers:
        - name: seed-config
          image: busybox:1.36
          command:
            - /bin/sh
            - -c
            - |
              if [ ! -f /opt/data/config.yaml ]; then
                sed -e "s|@LITELLM_BASE_URL@|${LITELLM_BASE_URL}|g" \
                    -e "s|@LITELLM_MODEL@|${LITELLM_MODEL}|g" \
                    /seed/config.yaml.tpl > /opt/data/config.yaml
                echo "seeded /opt/data/config.yaml"
              else
                echo "config.yaml already present; leaving as-is"
              fi
          env:
            - name: LITELLM_BASE_URL
              valueFrom:
                secretKeyRef:
                  name: hermes-secrets
                  key: LITELLM_BASE_URL
            - name: LITELLM_MODEL
              valueFrom:
                secretKeyRef:
                  name: hermes-secrets
                  key: LITELLM_MODEL
          volumeMounts:
            - name: data
              mountPath: /opt/data
            - name: config-tpl
              mountPath: /seed
      containers:
        - name: hermes
          image: nousresearch/hermes-agent:v2026.5.16
          command: ["hermes", "gateway", "run"]
          ports:
            - containerPort: 8642
              name: api
            - containerPort: 9119
              name: dashboard
          env:
            - name: API_SERVER_ENABLED
              value: "true"
            - name: API_SERVER_HOST
              value: "0.0.0.0"
            - name: HERMES_DASHBOARD
              value: "1"
            - name: API_SERVER_KEY
              valueFrom:
                secretKeyRef:
                  name: hermes-secrets
                  key: API_SERVER_KEY
            - name: LITELLM_API_KEY
              valueFrom:
                secretKeyRef:
                  name: hermes-secrets
                  key: LITELLM_API_KEY
          volumeMounts:
            - name: data
              mountPath: /opt/data
          resources:
            requests:
              cpu: "500m"
              memory: "1Gi"
            limits:
              cpu: "2"
              memory: "4Gi"
          livenessProbe:
            httpGet:
              path: /health
              port: 8642
            initialDelaySeconds: 60
            periodSeconds: 30
          readinessProbe:
            httpGet:
              path: /health
              port: 8642
            initialDelaySeconds: 15
            periodSeconds: 10
      volumes:
        - name: data
          persistentVolumeClaim:
            claimName: hermes-data
        - name: config-tpl
          configMap:
            name: hermes-config
```

- [ ] **Step 2: Validate YAML.**

Run: `python3 -c "import yaml; d=yaml.safe_load(open('/root/hermes/manifests/deployment.yaml')); assert d['kind']=='Deployment'; assert d['spec']['replicas']==1; ic=d['spec']['template']['spec']['initContainers']; assert len(ic)==1 and ic[0]['name']=='seed-config'; c=d['spec']['template']['spec']['containers'][0]; assert c['image']=='nousresearch/hermes-agent:v2026.5.16'; print('ok')"`
Expected: `ok`.

- [ ] **Step 3: Commit.**

```bash
cd /root/hermes && git add manifests/deployment.yaml && git commit -m "Add Deployment with init-container config templating"
```

---

## Task 7: `manifests/service.yaml`

**Files:**
- Create: `/root/hermes/manifests/service.yaml`

- [ ] **Step 1: Write `manifests/service.yaml`** — `ClusterIP`, portable:

```yaml
apiVersion: v1
kind: Service
metadata:
  name: hermes
  namespace: hermes
spec:
  type: ClusterIP
  selector:
    app: hermes
  ports:
    - name: api
      port: 8642
      targetPort: 8642
    - name: dashboard
      port: 9119
      targetPort: 9119
```

- [ ] **Step 2: Validate YAML.**

Run: `python3 -c "import yaml; d=yaml.safe_load(open('/root/hermes/manifests/service.yaml')); assert d['kind']=='Service' and d['spec']['type']=='ClusterIP' and len(d['spec']['ports'])==2; print('ok')"`
Expected: `ok`.

- [ ] **Step 3: Commit.**

```bash
cd /root/hermes && git add manifests/service.yaml && git commit -m "Add ClusterIP Service exposing :8642 and :9119"
```

---

## Task 8: Push the hermes repo

- [ ] **Step 1: Push to origin.**

Run: `cd /root/hermes && git push origin main`
Expected: commits land; `git rev-list --count origin/main..HEAD` → `0`.

---

## Task 9: `labops/hermes-vip/service.yaml` — MetalLB LoadBalancer overlay

**Files:**
- Create: `/root/labops/hermes-vip/service.yaml`

- [ ] **Step 1: Write the overlay manifest.**

```yaml
apiVersion: v1
kind: Service
metadata:
  name: vip-hermes
  namespace: hermes
  annotations:
    metallb.universe.tf/allow-shared-ip: host
spec:
  type: LoadBalancer
  selector:
    app: hermes
  ports:
    - name: api
      port: 8642
      targetPort: 8642
    - name: dashboard
      port: 9119
      targetPort: 9119
```

- [ ] **Step 2: Validate YAML.**

Run: `python3 -c "import yaml; d=yaml.safe_load(open('/root/labops/hermes-vip/service.yaml')); assert d['kind']=='Service' and d['spec']['type']=='LoadBalancer' and d['metadata']['annotations']['metallb.universe.tf/allow-shared-ip']=='host' and d['spec']['selector']['app']=='hermes'; print('ok')"`
Expected: `ok`.

- [ ] **Step 3: Commit.**

```bash
cd /root/labops && git add hermes-vip/service.yaml && git commit -m "Add hermes-vip MetalLB LoadBalancer overlay"
```

---

## Task 10: `labops/argo/services.yaml` — register `hermes` + `hermes-vip`

**Files:**
- Modify: `/root/labops/argo/services.yaml`

- [ ] **Step 1: Append two entries to the existing list** (after the `podinfo` entry):

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

- [ ] **Step 2: Validate the registry YAML and confirm both entries are present.**

Run: `python3 -c "import yaml; d=yaml.safe_load(open('/root/labops/argo/services.yaml')); assert isinstance(d, list); names=[e['name'] for e in d]; assert 'hermes' in names and 'hermes-vip' in names; print('entries:', names)"`
Expected: `entries: ['podinfo', 'hermes', 'hermes-vip']`.

- [ ] **Step 3: Commit.**

```bash
cd /root/labops && git add argo/services.yaml && git commit -m "services: register hermes and hermes-vip"
```

---

## Task 11: Push labops

- [ ] **Step 1: Push to origin.**

Run: `cd /root/labops && git push origin master`
Expected: `git rev-list --count origin/master..HEAD` → `0`.

---

## Task 12: Acceptance — apply `hermes-secrets` on the NUC  *(host-modifying)*

- [ ] **Step 1: Export the four env vars from `~/opencode.json` and generate `API_SERVER_KEY`.**

Run:
```bash
export LITELLM_BASE_URL=$(jq -r '.provider["litellm-router"].options.baseURL' /root/opencode.json)
export LITELLM_API_KEY=$(jq -r '.provider["litellm-router"].options.apiKey' /root/opencode.json)
export LITELLM_MODEL="smart-coder"
export API_SERVER_KEY=$(openssl rand -hex 32)
echo "LITELLM_BASE_URL=${LITELLM_BASE_URL}"
echo "LITELLM_MODEL=${LITELLM_MODEL}"
echo "API_SERVER_KEY length: ${#API_SERVER_KEY}"
```
Expected: the LiteLLM base URL prints (a Cloud Run URL); `LITELLM_MODEL=smart-coder`; `API_SERVER_KEY length: 64`. The `LITELLM_API_KEY` is intentionally not echoed.

- [ ] **Step 2: Apply the Secret.**

Run: `/root/hermes/set-secret`
Expected: `namespace/hermes configured` (or created); `secret/hermes-secrets created` (or configured); `hermes-secrets applied to namespace hermes`.

- [ ] **Step 3: Verify the Secret has the four keys.**

Run: `kubectl -n hermes get secret hermes-secrets -o jsonpath='{.data}' | jq 'keys'`
Expected: `["API_SERVER_KEY","LITELLM_API_KEY","LITELLM_BASE_URL","LITELLM_MODEL"]`.

---

## Task 13: Acceptance — Argo CD deploys Hermes + the overlay  *(host-modifying)*

- [ ] **Step 1: Restart the ApplicationSet controller to re-read `services.yaml`.**

Run:
```bash
kubectl -n argocd rollout restart deploy/argocd-applicationset-controller \
  && kubectl -n argocd rollout status deploy/argocd-applicationset-controller --timeout=120s
```
Expected: rollout succeeds.

- [ ] **Step 2: Poll until both Applications reach `Synced/Healthy` (cap ~5 min).**

Run:
```bash
n=0
until [[ "$(kubectl -n argocd get app hermes -o jsonpath='{.status.sync.status}/{.status.health.status}' 2>/dev/null)" == "Synced/Healthy" \
      && "$(kubectl -n argocd get app hermes-vip -o jsonpath='{.status.sync.status}/{.status.health.status}' 2>/dev/null)" == "Synced/Healthy" \
      || $n -ge 20 ]]; do
  n=$((n+1))
  printf '[%d] hermes=%s hermes-vip=%s\n' "$n" \
    "$(kubectl -n argocd get app hermes -o jsonpath='{.status.sync.status}/{.status.health.status}' 2>/dev/null || echo not-yet)" \
    "$(kubectl -n argocd get app hermes-vip -o jsonpath='{.status.sync.status}/{.status.health.status}' 2>/dev/null || echo not-yet)"
  sleep 15
done
echo "---"
kubectl -n argocd get applications | grep -E 'NAME|hermes'
```
Expected: both Applications eventually print `Synced/Healthy`.

- [ ] **Step 3: Verify cluster state in the `hermes` namespace.**

Run: `kubectl -n hermes get pods,svc,pvc`
Expected:
- a pod `hermes-…` `1/1 Running`,
- `service/hermes` `ClusterIP` exposing ports 8642 and 9119,
- `service/vip-hermes` `LoadBalancer` with `EXTERNAL-IP 192.168.1.250` exposing ports 8642 and 9119,
- `persistentvolumeclaim/hermes-data` `Bound`.

---

## Task 14: Acceptance — end-to-end test  *(host-modifying)*

- [ ] **Step 1: Retrieve `API_SERVER_KEY` from the Secret.**

Run:
```bash
API_SERVER_KEY=$(kubectl -n hermes get secret hermes-secrets -o jsonpath='{.data.API_SERVER_KEY}' | base64 -d)
echo "API_SERVER_KEY length: ${#API_SERVER_KEY}"
```
Expected: `API_SERVER_KEY length: 64`.

- [ ] **Step 2: Call `/v1/models` on the host IP.**

Run:
```bash
curl -fsS -H "Authorization: Bearer ${API_SERVER_KEY}" \
  http://192.168.1.250:8642/v1/models | head -c 2000
```
Expected: a JSON response listing the models Hermes exposes via the LiteLLM router (includes `smart-coder`).

- [ ] **Step 3: Make a tiny chat-completion call (full chain end-to-end).**

Run:
```bash
curl -fsS -X POST http://192.168.1.250:8642/v1/chat/completions \
  -H "Authorization: Bearer ${API_SERVER_KEY}" \
  -H "Content-Type: application/json" \
  -d '{"model":"smart-coder","messages":[{"role":"user","content":"say hi"}],"max_tokens":20}' \
  | head -c 2000
```
Expected: a JSON response with a `choices[].message.content` — confirms the full chain Hermes → LiteLLM router → `smart-coder`.

- [ ] **Step 4: Confirm the dashboard responds.**

Run: `curl -fsS -o /dev/null -w "HTTP %{http_code}\n" http://192.168.1.250:9119/`
Expected: `HTTP 200` (or `HTTP 3xx`) — any non-error code confirms the dashboard is serving.

---

## Done

After Task 14, a persistent Hermes agent is live on the NUC, GitOps-managed via the
`services` registry. The API is at `http://192.168.1.250:8642` (bearer-token guarded);
the dashboard at `http://192.168.1.250:9119`. Skills, sessions, and memory persist on the
`hermes-data` PVC across pod restarts.

To onboard another adopter of `apnex/hermes`: they clone the repo, set their four env
vars, run `./set-secret` against their cluster, and point their own GitOps tool at
`manifests/` — no fork needed for the common case.
