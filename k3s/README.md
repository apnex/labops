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
