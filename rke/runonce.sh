#!/bin/bash

if [[ -e /tmp/runonce ]]; then
	rm /tmp/runonce
	exec &> >(tee -a /root/newtest.log)
	curl -fsSL http://labops.sh/docker/install | sh
	echo "[[[ Completed Evolution: Stage 1 ]]]"

	curl -fsSL http://labops.sh/rke/install | sh
	echo "[[[ Completed Evolution: Stage 2 ]]]"

	export KUBECONFIG=/root/.kube/config
	curl -fsSL http://labops.sh/storage/install | sh
	curl -fsSL http://labops.sh/metallb/install | sh
	curl -fsSL http://labops.sh/metallb/prepare | sh
	echo "[[[ Completed Evolution: Stage 3 ]]]"
fi

exit
