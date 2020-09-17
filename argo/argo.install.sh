#!/bin/bash

## install cli
# https://argoproj.github.io/argo-cd/cli_installation/
# VERSION=$(curl --silent "https://api.github.com/repos/argoproj/argo-cd/releases/latest" | grep '"tag_name"' | sed -E 's/.*"([^"]+)".*/\1/')
# curl -sSL -o /usr/local/bin/argocd https://github.com/argoproj/argo-cd/releases/download/$VERSION/argocd-linux-amd64
# chmod +x /usr/local/bin/argocd

## install argo system
# https://argoproj.github.io/argo-cd/getting_started/
kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
kubectl apply -n argocd -f https://raw.githubusercontent.com/apnex/labops/master/argo/app.index.yaml
