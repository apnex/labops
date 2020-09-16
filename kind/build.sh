#!/bin/bash
CNAME='apnex/kind-proxy'
docker rm -f ${CNAME} 2>/dev/null
docker rm -v $(docker ps -qa -f name=${CNAME} -f status=exited) 2>/dev/null
docker rmi -f ${CNAME} 2>/dev/null

docker build --no-cache -t docker.io/apnex/kind-proxy -f kind-proxy.docker .
docker rmi -f $(docker images -q --filter label=stage=intermediate)
