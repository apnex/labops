# hermes-host-prep

One-shot, idempotent host prep for the Hermes pod.

## What it does

- Enables systemd linger for the audio user (default: `apnex`)
  so `/run/user/<uid>` exists from boot.
- This is required by the Hermes pod's `pulse-socket` hostPath mount.
  Without it, a headless reboot leaves voice mode permanently broken
  (the mount only succeeds if a user session has started).

## Usage

```bash
bash ~/labops/hermes-host-prep/up
# or with a different user:
HERMES_AUDIO_USER=greg bash ~/labops/hermes-host-prep/up
```

Safe to re-run — it detects existing linger state.

## To make it automatic on rebuilds

Add to `labops/k3s/runonce.sh` (after the k3s/up call):

```bash
bash "${LABOPS_ROOT}/hermes-host-prep/up"
```
