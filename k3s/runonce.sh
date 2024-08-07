#!/bin/bash

## Init
exec &> >(tee -a /root/startup.log)

## Stage 1+2
curl -fsSL http://labops.sh/k3s/install | sh
echo "[[[ Completed Evolution: Stage 2 ]]]"

## Stage 3
export KUBECONFIG=/root/.kube/config
curl -fsSL http://labops.sh/metallb/install | sh
curl -fsSL http://labops.sh/metallb/prepare | sh
echo "[[[ Completed Evolution: Stage 3 ]]]"

## Done
echo "1" > /root/startup.done

exit
