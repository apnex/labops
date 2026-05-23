# registry

In-cluster OCI registry — `docker.io/library/registry:2` exposed on the shared
LAN VIP `192.168.1.250:5000`. Argo CD deploys this from `labops/argo/services.yaml`.

## What it provides

| Endpoint | Reachable from | Purpose |
|---|---|---|
| `registry.registry.svc.cluster.local:5000` | Inside cluster | Pods pulling/pushing |
| `192.168.1.250:5000` | LAN | Host containerd pulls, external docker push, kaniko push |

## Image addressing

All images stored here are addressed as:

```
192.168.1.250:5000/<name>:<tag>
```

Use the same string in `image:` fields of Deployments and as Kaniko's
`--destination=` argument — kubelet (on host) and kaniko (in pod) both reach
the registry by that LAN IP.

## Host setup (one-time)

For k3s containerd to pull from this plaintext-HTTP registry, the host needs
`/etc/rancher/k3s/registries.yaml` populated. See `labops/k3s/registries.yaml`
for the canonical content; apply with:

```sh
sudo cp /root/labops/k3s/registries.yaml /etc/rancher/k3s/registries.yaml
sudo systemctl restart k3s
```

## No auth

The registry is anonymous read/write. Acceptable on a single-user LAN; add
htpasswd-based auth later if you ever expose externally. See the upstream
[`registry` image docs](https://hub.docker.com/_/registry) for the env vars.

## Storage

50Gi PVC on the `local-path` StorageClass — plenty for personal use. Image
layers and manifests live under `/var/lib/registry` in the pod
(`registry-data` PVC).

## Useful curl probes

```sh
# health
curl http://192.168.1.250:5000/v2/

# list repositories
curl http://192.168.1.250:5000/v2/_catalog

# list tags for a repo
curl http://192.168.1.250:5000/v2/<name>/tags/list
```
