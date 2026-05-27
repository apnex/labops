#!/bin/bash
## module: argo/runonce.sh
## purpose: VM first-boot shim — run the k3s stack + Argo CD, then signal completion
## inputs:  -
## needs:   k3s/up, argo/install, argo/set-service, argo/cli-install, argo/set-password

## must run as root; restore /usr/local/bin in PATH (RHEL sudo strips it)
[[ ${EUID:-$(id -u)} -eq 0 ]] || { echo "must be run as root" >&2; exit 1; }
export PATH="/usr/local/sbin:/usr/local/bin:${PATH}"

if [[ -e /tmp/runonce ]]; then
	rm /tmp/runonce
	exec &> >(tee -a /root/startup.log)

	## k3s host stack — k3s + MetalLB + storage + metrics
	curl -fsSL https://labops.sh/k3s/up | bash
	export KUBECONFIG=/root/.kube/config
	echo "[[[ Completed Evolution: k3s stack ]]]"

	## Argo CD platform
	curl -fsSL https://labops.sh/argo/install | sh
	curl -fsSL https://labops.sh/argo/set-service | sh
	curl -fsSL https://labops.sh/argo/cli-install | sh
	curl -fsSL https://labops.sh/argo/set-password | sh
	echo "[[[ Completed Evolution: Argo CD ]]]"
	echo "1" > /root/startup.done
fi

exit
