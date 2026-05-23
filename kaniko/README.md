# kaniko

In-cluster image builds via [Kaniko](https://github.com/GoogleContainerTools/kaniko)
— builds a Dockerfile from a Git repo and pushes the resulting OCI image to the
in-cluster registry at `192.168.1.250:5000`.

This is **not** an Argo Application (a build is an event, not a desired state).
The Kaniko Job manifest lives here as a template; `build.sh` substitutes it and
creates the Job imperatively. Stage 2 (Argo Workflows) is where these become
properly declarative.

## Quick start

```sh
# Build apnex/hermes image/Dockerfile at main, tag with short-SHA, push to registry
./build.sh apnex/hermes main image hermes
# -> 192.168.1.250:5000/hermes:<short-sha>

# Same with an explicit tag
./build.sh apnex/hermes main image hermes Dockerfile v2026.5.16-voice
# -> 192.168.1.250:5000/hermes:v2026.5.16-voice

# Build a repo where Dockerfile is at the root
./build.sh apnex/honcho main . honcho
# -> 192.168.1.250:5000/honcho:<short-sha>
```

The script:

1. Resolves the short-SHA of the requested ref from GitHub (for the tag if not given).
2. Substitutes placeholders in `buildjob.yaml.tpl` and creates a Job in the `kaniko` namespace.
3. Streams the pod's log until completion.
4. Reports success / failure / unclear state.

## What the build actually does

Kaniko inside the Pod:

1. Clones `git://github.com/<org>/<repo>.git#refs/heads/<ref>` into an emptyDir.
2. Changes to `<context-subdir>`.
3. Reads `<dockerfile>`, builds layer by layer using its own userspace
   tar/snapshotter (no daemon, no privileged container).
4. Pushes the result to `192.168.1.250:5000/<image-name>:<tag>` as plaintext HTTP
   (`--insecure --skip-tls-verify`).

Layer cache is shared across builds via `192.168.1.250:5000/kaniko-cache`
— first build of a new Dockerfile is slow, subsequent ones reuse layers from
the cache repo.

## Using the built image

In a Deployment manifest:

```yaml
spec:
  containers:
    - name: hermes
      image: 192.168.1.250:5000/hermes:<sha-or-tag>
      imagePullPolicy: IfNotPresent
```

kubelet pulls from the registry via the LAN IP. Requires the host containerd
config at `/etc/rancher/k3s/registries.yaml` (see `labops/k3s/registries.yaml`).

## Cleanup

Completed Jobs (and their Pods) auto-clean after 1 hour via
`ttlSecondsAfterFinished: 3600`. Failed Jobs stick around for the same period
so you can inspect them.

Manually:

```sh
kubectl -n kaniko delete job --all
```

## What this doesn't (yet) do

- **No webhook / auto-trigger.** You run `./build.sh` manually. Stage 2 (Argo
  Workflows) + Stage 3 (Argo Events) automate this end-to-end.
- **No manifest bump.** After a build, you still edit the image tag in the
  consuming repo (`apnex/hermes` `manifests/deployment.yaml`) and let Argo CD
  reconcile. Argo Image Updater could automate this; not included in stage 1.
- **No private-repo auth.** Public repos work without credentials. Private repo
  support requires a Secret with a GitHub PAT mounted into the kaniko Pod.
