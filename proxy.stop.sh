#!/bin/bash

SERVICENAME="proxy"
IMAGENAME="kind-proxy"

printf "[apnex/${IMAGENAME}] stopping\n" 1>&2
docker rm -f "${SERVICENAME}" 2>/dev/null

# remove dangling image
docker rm -v $(docker ps -qa -f name="${IMAGENAME}" -f status=exited) 2>/dev/null

echo "-- removing untagged containers --"
docker rmi -f $(docker images -q --filter dangling=true) 2>/dev/null
echo "-- removing orphaned volumes --"
docker rm -f $(docker ps -qa -f status=exited) 2>/dev/null

exit 0
