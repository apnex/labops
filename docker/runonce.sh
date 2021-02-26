#!/bin/bash

if [[ -e /tmp/runonce ]]; then
	rm /tmp/runonce
	exec &> >(tee -a /root/startup.log)
	curl -fsSL http://labops.sh/docker/install | sh
	echo "[[[ Completed Evolution: Stage 1 ]]]"
	echo "1" > /root/startup.done
fi

exit
