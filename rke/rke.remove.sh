#!/bin/bash
echo "### teardown rke cluster ###"
sleep 1
echo "y" | rke remove --config ./rke.config.yaml

echo "### clear rancher images ###"
sleep 1
echo "-- shutting down running containers --"
docker rm -f -v $(docker ps -qa) 2>/dev/null
echo "-- removing all images --"
docker rmi -f $(docker images -qa) 2>/dev/null
echo "-- performing docker system prune --"
docker system prune -a -f

echo "### remove kubeconfig ###"
sleep 1
rm -rf $HOME/.kube

echo "### remove kubectl ###"
sleep 1
rm -f /usr/local/bin/kubectl

echo "### remove kubectl ###"
sleep 1
rm -f /usr/local/bin/rke

echo "### remove rke service account ###"
userdel -r rke
