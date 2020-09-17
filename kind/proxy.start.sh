#!/bin/bash
# This launches the kind-proxy container as a daemon on host

docker run -d --net=host --cap-add=NET_ADMIN --cap-add=NET_RAW \
	--name=kind-proxy \
	-v /root/.kube/config:/root/.kube/config \
apnex/kind-proxy
