#!/bin/bash

if [[ -e /tmp/runonce ]]; then
	rm /tmp/runonce
	exec > /root/runonce.log 2>&1
	curl -fsSL http://labops.sh/docker/install | sh
	curl -fsSL http://labops.sh/rke/install | sh
fi

exit
