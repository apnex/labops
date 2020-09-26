#!/bin/bash

## install metrics server
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml

## patch metrics server
#This ensures that metric server can securely connect to localhost:443
./metrics.patch.sh
