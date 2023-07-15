#!/bin/bash

if [[ -e /tmp/runonce ]]; then
	rm /tmp/runonce
	exec &> >(tee -a /root/startup.log)
	curl -fsSL https://labops.sh/docker/install | sh
	echo "[[[ Completed Evolution: Stage 1 ]]]"

	curl -fsSL https://labops.sh/rke/install | sh
	export KUBECONFIG=/root/.kube/config
	echo "[[[ Completed Evolution: Stage 2 ]]]"

	curl -fsSL https://labops.sh/storage/install | sh
	curl -fsSL https://labops.sh/metallb/install | sh
	curl -fsSL https://labops.sh/metallb/prepare | sh
	echo "[[[ Completed Evolution: Stage 3 ]]]"

	curl -fsSL https://labops.sh/argo/install | sh
	curl -fsSL https://labops.sh/argo/set-service | sh
	curl -fsSL https://labops.sh/argo/cli-install | sh
	curl -fsSL https://labops.sh/argo/set-password | sh
	echo "[[[ Completed Evolution: Stage 4 ]]]"
	echo "1" > /root/startup.done
fi

exit
