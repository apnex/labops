#!/bin/bash
# This launches the kind-proxy container as a daemon on host

# remove dangling image
docker rm -v $(docker ps -qa -f name="kind-proxy" -f status=exited) 2>/dev/null

docker run -d --net=host --cap-add=NET_ADMIN --cap-add=NET_RAW \
	--name=kind-proxy \
	-v /root/.kube/config:/root/.kube/config \
apnex/kind-proxy
