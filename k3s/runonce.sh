#!/bin/bash
## module: k3s/runonce.sh
## purpose: VM first-boot shim — run the k3s host stack + hermes host prep,
##          then signal completion
## inputs:  -
## needs:   k3s/up, hermes-host-prep/up

## must run as root; restore /usr/local/bin in PATH (RHEL sudo strips it)
[[ ${EUID:-$(id -u)} -eq 0 ]] || { echo "must be run as root" >&2; exit 1; }
export PATH="/usr/local/sbin:/usr/local/bin:${PATH}"

set -euo pipefail

LABOPS_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
if [[ -f "${LABOPS_ROOT}/k3s/up" ]]; then
	bash "${LABOPS_ROOT}/k3s/up"
else
	curl -fsSL "${LABOPS_BASE:-https://labops.sh}/k3s/up" | bash
fi

## Hermes-specific host prep (linger for audio user, etc.)
## Non-fatal: failures here log a warning but don't block startup completion.
if [[ -f "${LABOPS_ROOT}/hermes-host-prep/up" ]]; then
	bash "${LABOPS_ROOT}/hermes-host-prep/up" || \
		echo "[ RUNONCE ] WARNING: hermes-host-prep/up failed — voice mode may be unavailable" 1>&2
else
	echo "[ RUNONCE ] hermes-host-prep/up not present — skipping (voice mode setup deferred)"
fi

## VM-stage completion sentinel — reached only if k3s/up succeeded (log: /root/k3s-install.log)
echo "1" > /root/startup.done
exit 0
