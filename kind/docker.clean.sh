#!/bin/bash
echo "-- shutting down running containers --"
docker rm -f -v $(docker ps -qa) 2>/dev/null
echo "-- removing all images --"
docker rmi -f $(docker images -qa) 2>/dev/null
echo "-- performing docker system prune --"
docker system prune -a -f
