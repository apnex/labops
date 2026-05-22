#!/bin/bash
## module: k3s/runonce.sh
## purpose: VM first-boot shim — run the k3s host stack, then signal completion
## inputs:  -
## needs:   k3s/up
set -euo pipefail

LABOPS_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
if [[ -f "${LABOPS_ROOT}/k3s/up" ]]; then
	bash "${LABOPS_ROOT}/k3s/up"
else
	curl -fsSL "${LABOPS_BASE:-https://labops.sh}/k3s/up" | bash
fi

## VM-stage completion sentinel — reached only if k3s/up succeeded (log: /root/k3s-install.log)
echo "1" > /root/startup.done
exit 0
