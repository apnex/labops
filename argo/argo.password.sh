#!/bin/bash

## get pod name for password
kubectl get pods -n argocd -l app.kubernetes.io/name=argocd-server -o name | cut -d'/' -f 2

## change password
#argocd login 172.19.255.2 --insecure
#argocd account update-password \
#  --account <name> \
#  --current-password <current-admin> \
#  --new-password <new-user-password>
