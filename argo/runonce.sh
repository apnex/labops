#!/bin/bash

if [[ -e /tmp/runonce ]]; then
	rm /tmp/runonce
	exec &> >(tee -a /root/startup.log)
	curl -fsSL http://labops.sh/docker/install | sh
	echo "[[[ Completed Evolution: Stage 1 ]]]"

	curl -fsSL http://labops.sh/rke/install | sh
	export KUBECONFIG=/root/.kube/config
	echo "[[[ Completed Evolution: Stage 2 ]]]"

	curl -fsSL http://labops.sh/storage/install | sh
	curl -fsSL http://labops.sh/metallb/install | sh
	curl -fsSL http://labops.sh/metallb/prepare | sh
	echo "[[[ Completed Evolution: Stage 3 ]]]"

	curl -fsSL http://labops.sh/argo/install | sh
	curl -fsSL http://labops.sh/argo/set-password | sh
	curl -fsSL http://labops.sh/argo/set-service | sh
	echo "[[[ Completed Evolution: Stage 4 ]]]"
fi

exit
